import AppKit
import ApplicationServices

/// All mutable cache/scheduling state belongs to the main run loop. Blocking AX
/// work runs on one serial worker and publishes only immutable value snapshots.
/// Requests coalesce; invalidation generations reject stale in-flight results.
public protocol ScrollTargetProviding: AnyObject {
    var onChange: ((ScrollTarget?) -> Void)? { get set }
    var onProbe: ((Double, Bool) -> Void)? { get set }
    func start(at point: CGPoint)
    func stop()
    func target(at point: CGPoint) -> ScrollTarget?
    func invalidate(at point: CGPoint)
    func request(at point: CGPoint)
}

public final class ScrollTargetResolver: ScrollTargetProviding {
    public typealias Lookup = @Sendable (CGPoint) -> ScrollTarget?
    private let worker = DispatchQueue(label: "local.smoothwheel.target", qos: .userInitiated)
    private let lookup: Lookup
    private var generation = 0
    private var desiredPoint: CGPoint?
    private var scheduled: DispatchWorkItem?
    private var inFlight = false
    private var active = false
    private var cached: ScrollTarget?
    public var onChange: ((ScrollTarget?) -> Void)?
    public var onProbe: ((Double, Bool) -> Void)?

    public init(lookup: Lookup? = nil) {
        if let lookup { self.lookup = lookup }
        else { self.lookup = { point in Self.systemLookup(at: point) } }
    }

    public func start(at point: CGPoint) {
        precondition(Thread.isMainThread)
        active = true; invalidate(at: point)
    }
    public func stop() {
        precondition(Thread.isMainThread)
        active = false; generation += 1; scheduled?.cancel(); scheduled = nil
        desiredPoint = nil; publish(nil)
    }
    public func target(at point: CGPoint) -> ScrollTarget? {
        precondition(Thread.isMainThread)
        guard let cached, cached.bounds.contains(point) else { return nil }
        return cached
    }
    public func invalidate(at point: CGPoint) {
        precondition(Thread.isMainThread)
        generation += 1; publish(nil); request(at: point)
    }
    public func request(at point: CGPoint) {
        precondition(Thread.isMainThread)
        guard active else { return }
        desiredPoint = point
        if let cached, !cached.bounds.contains(point) { publish(nil) }
        guard scheduled == nil, !inFlight else { return }
        let work = DispatchWorkItem { [weak self] in self?.beginLookup() }
        scheduled = work
        // Bound AX request frequency even with a 1000 Hz mouse. No polling while idle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }
    private func beginLookup() {
        precondition(Thread.isMainThread)
        scheduled = nil
        guard active, let point = desiredPoint else { return }
        desiredPoint = nil; inFlight = true
        let revision = generation
        let lookup = self.lookup
        worker.async { [weak self] in
            let began = ProcessInfo.processInfo.systemUptime
            let result = lookup(point)
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                guard self.active else { return }
                self.onProbe?(elapsed, result != nil)
                let currentPoint = self.desiredPoint ?? point
                if revision == self.generation, let result, result.bounds.contains(currentPoint) {
                    self.publish(result)
                }
                // A failed probe leaves a still-valid snapshot intact. A pointer
                // departure or explicit invalidation already cleared it above.
                if self.desiredPoint != nil { self.request(at: currentPoint) }
            }
        }
    }
    private func publish(_ target: ScrollTarget?) {
        guard target != cached else { return }
        cached = target; onChange?(target)
    }

    private static func systemLookup(at point: CGPoint) -> ScrollTarget? {
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.05)
        var element: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element) == .success,
              let element, AXUIElementGetPid(element, &pid) == .success,
              let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.05)
        var windowValue: CFTypeRef?
        let window: AXUIElement
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
            // CoreFoundation values are bridged only after checking their type IDs.
            window = windowValue as! AXUIElement
        } else { window = element }
        AXUIElementSetMessagingTimeout(window, 0.05)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        let bounds = CGRect(origin: origin, size: extent)
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        return ScrollTarget(owner: owner, bounds: bounds)
    }
}
