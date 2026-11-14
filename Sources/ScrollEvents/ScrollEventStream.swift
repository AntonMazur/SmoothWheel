import CoreGraphics
import Dispatch
import ScrollCore

/// Stateful event-to-frame conversion. No event tap, event posting, or global input reads.
/// The same path is used by the runtime and by the CGEvent regression tests.
public final class ScrollEventStream {
    public static let marker: Int64 = 0x53574C31
    public static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
    /// Product baseline: the 1× setting travels three times the native wheel distance.
    public static let baseSpeedMultiplier = 3.0
    public var speed = 1.0
    public var smoothing = 0.45
    public var reversed = false
    private var vertical = ScrollSmoother()
    private var horizontal = ScrollSmoother()
    private var prepared = false
    private var flags: CGEventFlags = []
    private let makeEvent: (Int32, Int32) -> CGEvent?

    public init(makeEvent: ((Int32, Int32) -> CGEvent?)? = nil) {
        if let makeEvent { self.makeEvent = makeEvent }
        else {
            // This source is private to the synthetic stream, with no hardware suppression.
            let source = CGEventSource(stateID: .privateState)
            source?.localEventsSuppressionInterval = 0
            source?.pixelsPerLine = 10
            self.makeEvent = { x, y in
                CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
            }
        }
    }

    public var hasPendingFrames: Bool { vertical.remaining != 0 || horizontal.remaining != 0 }
    public var modifiers: CGEventFlags { flags }

    public static func meaningfulModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(modifierMask)
    }

    public static func shouldBypass(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ||
        !event.flags.intersection([.maskAlternate, .maskControl, .maskCommand]).isEmpty ||
        event.getIntegerValueField(.scrollWheelEventDeltaAxis3) != 0
    }

    /// Preserve the OS-provided pixel distance/acceleration instead of replacing it with
    /// a hardcoded multiple of rounded line ticks. Some wheels only populate point/fixed fields.
    public static func pixels(of event: CGEvent, axis: Int) -> Double {
        let point: CGEventField = axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
        let fixed: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let line: CGEventField = axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        let points = Double(event.getIntegerValueField(point))
        if points != 0 { return points }
        let lines = event.getDoubleValueField(fixed)
        if lines.isFinite && lines != 0 { return lines * 10 }
        return Double(event.getIntegerValueField(line)) * 10
    }

    /// Return true only after we have a successfully allocated replacement event. Otherwise
    /// the caller must pass the original event through untouched.
    public func accept(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker,
              !Self.shouldBypass(event) else { return false }
        let y = Self.pixels(of: event, axis: 1)
        let x = Self.pixels(of: event, axis: 2)
        guard y.isFinite, x.isFinite, y != 0 || x != 0 else { return false }
        if !prepared {
            guard makeEvent(0, 0) != nil else { return false }
            prepared = true
        }
        flags = Self.meaningfulModifiers(event.flags)
        let scale = Self.baseSpeedMultiplier * min(3, max(0.3, speed)) * (reversed ? -1.0 : 1.0)
        vertical.add(y * scale); horizontal.add(x * scale)
        return true
    }

    public func nextFrame(seconds: Double) -> CGEvent? {
        // Commit the integration only after the replacement allocation succeeds.
        var nextVertical = vertical
        var nextHorizontal = horizontal
        let y = nextVertical.step(seconds: seconds, smoothing: smoothing)
        let x = nextHorizontal.step(seconds: seconds, smoothing: smoothing)
        if x == 0 && y == 0 {
            vertical = nextVertical; horizontal = nextHorizontal
            if !hasPendingFrames { prepared = false }
            return nil
        }
        guard let event = makeFrame(x: x, y: y) else { return nil }
        vertical = nextVertical; horizontal = nextHorizontal
        if !hasPendingFrames { prepared = false }
        return event
    }

    public func reset() {
        vertical.reset(); horizontal.reset(); prepared = false
    }

    private func makeFrame(x: Int32, y: Int32) -> CGEvent? {
        // Construct each pixel event with fresh deltas and timestamp. Quartz maintains
        // the linked point/fixed/line fields; setting them individually can quantize
        // small pixel frames back to zero on macOS.
        guard let event = makeEvent(x, y) else { return nil }
        event.timestamp = DispatchTime.now().uptimeNanoseconds
        // The freshly constructed event already carries the current cursor position.
        // Replaying the input tick's old location can pull the pointer backwards
        // while the smoothing tail is still being posted.
        event.flags = flags
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        // These are precise mouse-wheel events, not trackpad gestures. Artificial
        // gesture phases can cause native scroll views to ignore an unattached stream.
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        return event
    }
}
