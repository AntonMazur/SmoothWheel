import AppKit
import QuartzCore

/// Main-run-loop clock tied to the display under the wheel event, not our settings window.
/// It runs only while scroll distance is pending. No background mutation or queued frame backlog.
public final class ScrollFrameClock {
    public init() {}
    private final class Target: NSObject {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
        @objc func frame(_ sender: Any) { handler() }
    }
    private var invalidate: (() -> Void)?
    private var target: Target?
    private var displayID: CGDirectDisplayID?
    private var displayBounds: CGRect?
    public private(set) var mode = "stopped"
    public var isRunning: Bool { invalidate != nil }

    /// Fast path for subsequent notches: no CoreGraphics or AppKit screen lookup.
    public func isTracking(_ point: CGPoint) -> Bool {
        precondition(Thread.isMainThread)
        return isRunning && (displayBounds?.contains(point) ?? false)
    }

    public func start(at point: CGPoint, handler: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        if isTracking(point) { return }
        var display = CGMainDisplayID()
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &display, &count) != .success || count == 0 { display = CGMainDisplayID() }
        if isRunning, displayID == display { return }
        stop()
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display } ?? NSScreen.main
        let target = Target(handler: handler)
        self.target = target; displayID = display; displayBounds = CGDisplayBounds(display)
        if #available(macOS 14.0, *), let screen {
            let link = screen.displayLink(target: target, selector: #selector(Target.frame(_:)))
            let maximum = Float(max(30, screen.maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            invalidate = { link.invalidate() }
            mode = "displayLink"
        } else {
            // macOS 13 compatibility; modern systems use the display link above.
            let rate = Double(max(30, screen?.maximumFramesPerSecond ?? 60))
            let timer = Timer(timeInterval: 1 / rate, repeats: true) { [weak target] _ in target?.handler() }
            timer.tolerance = 0.0005
            RunLoop.main.add(timer, forMode: .common)
            invalidate = { timer.invalidate() }
            mode = "timerFallback"
        }
    }

    public func stop() {
        precondition(Thread.isMainThread)
        invalidate?(); invalidate = nil
        target = nil; displayID = nil; displayBounds = nil; mode = "stopped"
    }
    deinit { invalidate?() }
}
