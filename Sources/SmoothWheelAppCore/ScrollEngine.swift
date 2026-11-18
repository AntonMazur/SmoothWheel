import AppKit
import ApplicationServices
import ScrollEvents
import ScrollTiming

/// Main-loop coordinator. The event tap and frame callbacks only consume local
/// state; Accessibility IPC belongs to ScrollTargetResolver's serial worker.
final class ScrollEngine: NSObject {
    static let inputTapLocation = CGEventTapLocation.cgAnnotatedSessionEventTap
    var enabled = false { didSet { resetInput(); updateTargetResolution() } }
    var speed: Double { get { stream.speed } set { stream.speed = newValue } }
    var smoothing: Double { get { stream.smoothing } set { stream.smoothing = newValue } }
    var reversed: Bool { get { stream.reversed } set { stream.reversed = newValue } }
    var excluded = Set<String>() { didSet { resetInput(); updateTargetResolution() } }
    private let stream = ScrollEventStream()
    private let diagnostics: ScrollDiagnostics?
    private let targets: ScrollTargetProviding
    private let uptime: () -> Double
    private let postEvent: (CGEvent) -> Void
    private let recipientOwner: (Int64) -> String?
    private var routing = ScrollRoutingState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let frameClock: ScrollFrameClock
    private var lastFrame = 0.0
    private var motionRecipient: Int64?
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var isAnimating: Bool { frameClock.isRunning }

    private func updateTargetResolution() {
        if enabled, !excluded.isEmpty, let point = CGEvent(source: nil)?.location {
            targets.start(at: point)
        } else { targets.stop() }
    }
    private func resetInput() { routing.reset(); cancelMotion() }

    override convenience init() {
        let recipients = ScrollRecipientRegistry()
        self.init(targets: ScrollTargetResolver(), frameClock: ScrollFrameClock(),
            uptime: { ProcessInfo.processInfo.systemUptime }, postEvent: { $0.post(tap: .cgSessionEventTap) },
            diagnostics: ScrollDiagnostics.fromEnvironment(), recipientOwner: recipients.owner(for:))
    }
    init(targets: ScrollTargetProviding, frameClock: ScrollFrameClock = ScrollFrameClock(),
         uptime: @escaping () -> Double, postEvent: @escaping (CGEvent) -> Void,
         diagnostics: ScrollDiagnostics? = nil, recipientOwner: @escaping (Int64) -> String? = { _ in nil }) {
        self.targets = targets; self.frameClock = frameClock
        self.uptime = uptime; self.postEvent = postEvent; self.diagnostics = diagnostics
        self.recipientOwner = recipientOwner
        super.init()
        targets.onChange = { [weak self] _ in
            // A delayed AX result must not override a WindowServer recipient.
            if self?.motionRecipient == nil { self?.cancelMotion() }
        }
        targets.onProbe = { [weak self] elapsed, succeeded in self?.diagnostics?.targetProbe(seconds: elapsed, succeeded: succeeded) }
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
        let events: [CGEventType] = [.scrollWheel, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: Self.inputTapLocation, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap); return false
        }
        tap = newTap; source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return running
    }

    func stop() {
        resetInput(); targets.stop()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetInput()
            if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == ScrollEventStream.marker { return Unmanaged.passUnretained(event) }
        let began = diagnostics != nil && type == .scrollWheel ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let began { diagnostics?.inputDuration(ProcessInfo.processInfo.systemUptime - began) } }
        if type == .flagsChanged {
            if ScrollEventStream.meaningfulModifiers(event.flags) != stream.modifiers { resetInput() }
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let pid = event.getIntegerValueField(.eventTargetUnixProcessID)
            if let motionRecipient, pid > 0, pid != motionRecipient { resetInput() }
            if enabled, !excluded.isEmpty, pid <= 0 { targets.request(at: event.location) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetInput()
            if enabled, !excluded.isEmpty { targets.invalidate(at: event.location) }
            return Unmanaged.passUnretained(event)
        default: break
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        guard enabled, !ScrollEventStream.shouldBypass(event) else {
            diagnostics?.bypassed(event)
            resetInput(); return Unmanaged.passUnretained(event)
        }
        let pid = event.getIntegerValueField(.eventTargetUnixProcessID)
        let owner: String?
        if pid > 0 {
            // The receiving process is authoritative. Never substitute a stale
            // hit-test owner when an annotated PID has not yet been registered.
            owner = recipientOwner(pid)
        } else {
            owner = targets.target(at: event.location)?.owner
            if !excluded.isEmpty { targets.request(at: event.location) }
        }
        diagnostics?.destination(processID: pid, ownerResolved: owner != nil)
        let now = uptime()
        let decision = routing.decide(owner: owner, excluded: excluded, time: now, recipientPID: pid > 0 ? pid : nil)
        if decision.resetMotion { cancelMotion() }
        diagnostics?.route(owner: owner ?? "unresolved", bypass: decision.mode == .native)
        guard decision.mode == .smooth else {
            cancelMotion(); return Unmanaged.passUnretained(event)
        }
        if stream.hasPendingFrames && ScrollEventStream.meaningfulModifiers(event.flags) != stream.modifiers { resetInput() }
        guard stream.accept(event) else {
            cancelMotion(); routing.useNativeForBurst()
            return Unmanaged.passUnretained(event)
        }
        motionRecipient = pid > 0 ? pid : nil
        diagnostics?.acceptedWheel()
        if !frameClock.isRunning { lastFrame = uptime() }
        if !frameClock.isTracking(event.location) {
            frameClock.start(at: event.location) { [weak self] in self?.tick() }
        }
        diagnostics?.clockMode(frameClock.mode)
        return nil
    }

    func tick() {
        let now = uptime()
        let elapsed = now - lastFrame; lastFrame = now
        guard enabled else { resetInput(); return }
        // Sleep, a long suspension, or a blocked run loop must not replay stale momentum.
        guard elapsed < 0.5 else { resetInput(); return }
        diagnostics?.frameInterval(elapsed)
        if let event = stream.nextFrame(seconds: elapsed) {
            diagnostics?.output(event)
            postEvent(event)
        }
        if !stream.hasPendingFrames { frameClock.stop(); motionRecipient = nil; diagnostics?.flush() }
    }

    @objc private func applicationChanged() {
        resetInput(); updateTargetResolution()
    }
    @objc private func sessionInterrupted() { resetInput(); updateTargetResolution() }

    func cancel() { resetInput() }
    private func cancelMotion() {
        frameClock.stop(); stream.reset(); motionRecipient = nil; diagnostics?.flush()
    }
}
