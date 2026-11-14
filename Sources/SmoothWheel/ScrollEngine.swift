import AppKit
import ApplicationServices
import ScrollEvents
import ScrollTiming

/// The tap, stream and display frame clock share the main run loop in common
/// modes, with no Accessibility/Workspace/pointer polling on its hot path.
final class ScrollEngine: NSObject {
    var enabled = false { didSet { if !enabled { cancel() } } }
    var speed: Double { get { stream.speed } set { stream.speed = newValue } }
    var smoothing: Double { get { stream.smoothing } set { stream.smoothing = newValue } }
    var reversed: Bool { get { stream.reversed } set { stream.reversed = newValue } }
    var excluded = Set<String>()
    private let stream = ScrollEventStream()
    private let diagnostics = ScrollDiagnostics.fromEnvironment()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let frameClock = ScrollFrameClock()
    private var lastFrame = 0.0
    private var foregroundApplication: NSRunningApplication?
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    override init() {
        super.init()
        foregroundApplication = NSWorkspace.shared.frontmostApplication
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterrupted), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionInterrupted), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionInterrupted), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }
    deinit {
        // The tap callback borrows self, so invalidate it before releasing the engine.
        stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func start() -> Bool {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return false }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return running }
        let events: [CGEventType] = [.scrollWheel, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap); return false
        }
        tap = newTap; source = runLoopSource
        foregroundApplication = NSWorkspace.shared.frontmostApplication
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return running
    }

    func stop() {
        cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel()
            if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == ScrollEventStream.marker { return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            if ScrollEventStream.meaningfulModifiers(event.flags) != stream.modifiers { cancel() }
            return Unmanaged.passUnretained(event)
        }
        if type != .scrollWheel { cancel(); return Unmanaged.passUnretained(event) }
        guard enabled, !excluded.contains(foregroundApplication?.bundleIdentifier ?? ""),
              !ScrollEventStream.shouldBypass(event) else {
            diagnostics?.bypassed(event)
            cancel(); return Unmanaged.passUnretained(event)
        }
        if stream.hasPendingFrames && ScrollEventStream.meaningfulModifiers(event.flags) != stream.modifiers { cancel() }
        guard stream.accept(event) else { return Unmanaged.passUnretained(event) }
        diagnostics?.acceptedWheel()
        if !frameClock.isRunning { lastFrame = ProcessInfo.processInfo.systemUptime }
        if !frameClock.isTracking(event.location) {
            frameClock.start(at: event.location) { [weak self] in self?.tick() }
        }
        diagnostics?.clockMode(frameClock.mode)
        return nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastFrame; lastFrame = now
        guard enabled else { cancel(); return }
        // Sleep, a long suspension, or a blocked run loop must not replay stale momentum.
        guard elapsed < 0.5 else { cancel(); return }
        diagnostics?.frameInterval(elapsed)
        if let event = stream.nextFrame(seconds: elapsed) {
            diagnostics?.output(event)
            event.post(tap: .cgSessionEventTap)
        }
        if !stream.hasPendingFrames { frameClock.stop(); diagnostics?.flush() }
    }

    @objc private func applicationChanged() {
        cancel(); foregroundApplication = NSWorkspace.shared.frontmostApplication
    }
    @objc private func sessionInterrupted() { cancel() }

    func cancel() {
        frameClock.stop()
        stream.reset()
        diagnostics?.flush()
    }
}
