import AppKit
import Testing
@testable import ScrollEvents

private func wheel(y: Int32 = 3, x: Int32 = 0, flags: CGEventFlags = []) throws -> CGEvent {
    let source = try #require(CGEventSource(stateID: .privateState))
    source.pixelsPerLine = 10
    let event = try #require(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
    event.flags = flags; event.location = CGPoint(x: 400, y: 300)
    return event
}

private func drain(_ stream: ScrollEventStream, intervals: [Double] = [1 / 120]) -> [CGEvent] {
    var events: [CGEvent] = []
    for index in 0..<1200 {
        if !stream.hasPendingFrames { break }
        if let event = stream.nextFrame(seconds: intervals[index % intervals.count]) { events.append(event) }
    }
    return events
}

@Test func outputPreservesNativePixelDistanceWithoutTrackpadPhases() throws {
    let input = try wheel()
    // Reproduce a wheel whose OS-accelerated point distance differs from line ticks.
    input.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 87)
    let stream = ScrollEventStream()
    #expect(stream.accept(input))
    let frames = drain(stream)
    #expect(frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } == 261)
    #expect(frames.allSatisfy { $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 0 })
    #expect(frames.allSatisfy { $0.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 })
    #expect(frames.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ScrollEventStream.marker })
    #expect(!stream.hasPendingFrames)
}

@Test func transientMouseFlagsDoNotDropRepeatedInput() throws {
    let stream = ScrollEventStream()
    let first = try wheel(flags: [.maskNonCoalesced])
    let second = try wheel(flags: [])
    #expect(ScrollEventStream.meaningfulModifiers(first.flags) == ScrollEventStream.meaningfulModifiers(second.flags))
    #expect(stream.accept(first))
    var frames: [CGEvent] = []
    for _ in 0..<40 { if let event = stream.nextFrame(seconds: 1 / 120) { frames.append(event) } }
    // More than the old 250ms cutoff: remaining distance must survive.
    #expect(stream.accept(second))
    frames += drain(stream)
    let expected = 3 * (ScrollEventStream.pixels(of: first, axis: 1) + ScrollEventStream.pixels(of: second, axis: 1))
    let total = frames.reduce(0.0) { $0 + Double($1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) }
    #expect(abs(total - expected) <= 1)
}

@Test func ordinaryPointerMotionDoesNotCancelPendingDistance() throws {
    let stream = ScrollEventStream()
    let first = try wheel()
    let second = try wheel()
    second.location = CGPoint(x: 407, y: 305)
    #expect(stream.accept(first))
    #expect(stream.accept(second))
    let frames = drain(stream)
    #expect(frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } == 180)
}

@Test func pointOnlyAndFractionalLineWheelsAreNotIgnored() throws {
    let input = try wheel(y: 0)
    input.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 37)
    let stream = ScrollEventStream()
    #expect(stream.accept(input))
    #expect(drain(stream).reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } == 111)
    input.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
    input.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.5)
    #expect(stream.accept(input))
    #expect(drain(stream).reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } == 15)
}

@Test func cancellationStopsPendingOutputBeforeBypass() throws {
    let stream = ScrollEventStream()
    #expect(stream.accept(try wheel()))
    #expect(stream.nextFrame(seconds: 1 / 60) != nil)
    stream.reset()
    #expect(stream.nextFrame(seconds: 1 / 60) == nil)
    #expect(!stream.hasPendingFrames)
}

@Test func trackpadAndShortcutEventsPassThrough() throws {
    let stream = ScrollEventStream()
    let trackpad = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: 0, wheel3: 0))
    #expect(!stream.accept(trackpad))
    for flag: CGEventFlags in [.maskAlternate, .maskCommand, .maskControl] {
        #expect(!stream.accept(try wheel(flags: flag)))
    }
    let own = try wheel()
    own.setIntegerValueField(.eventSourceUserData, value: ScrollEventStream.marker)
    #expect(!stream.accept(own))
}

@Test func failedReplacementAllocationLeavesOriginalUnsuppressed() throws {
    let stream = ScrollEventStream(makeEvent: { _, _ in nil })
    #expect(!stream.accept(try wheel()))
    #expect(!stream.hasPendingFrames)
}

@Test func irregularFramesPreserveHorizontalAndVerticalDistance() throws {
    let stream = ScrollEventStream()
    stream.speed = 1.2; stream.reversed = true
    #expect(stream.accept(try wheel(y: 10, x: -5)))
    let frames = drain(stream, intervals: [1 / 120, 1 / 60, 0.07, 1 / 144])
    #expect(abs(frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } + 360) <= 1)
    #expect(abs(frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) } - 180) <= 1)
}

@Test @MainActor func appKitReceivesCorrectPreciseDeltasAndPhases() throws {
    let stream = ScrollEventStream()
    #expect(stream.accept(try wheel()))
    let frames = drain(stream)
    var received = 0.0
    var maxError = 0.0
    for frame in frames {
        let native = try #require(NSEvent(cgEvent: frame))
        #expect(native.hasPreciseScrollingDeltas)
        let observed = Double(native.scrollingDeltaY)
        let expected = Double(frame.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        maxError = max(maxError, abs(observed - expected))
        #expect(abs(observed - expected) < 0.001)
        received += observed
    }
    print("AppKit conversion maximum pixel error: \(maxError)")
    #expect(abs(received - 90) < 0.001)
    #expect(frames.allSatisfy { NSEvent(cgEvent: $0)?.phase == [] })
}

@Test func framesHaveFreshMonotonicTimestamps() throws {
    let stream = ScrollEventStream()
    #expect(stream.accept(try wheel(y: 10)))
    let events = drain(stream)
    #expect(events.count > 2)
    for (first, second) in zip(events, events.dropFirst()) {
        #expect(second.timestamp > first.timestamp)
    }
}

@MainActor private final class TestScrollDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Dispatch the generated sequence into a real, unshown AppKit scroll view.
/// This does not post any events globally or change the user's foreground app.
@Test @MainActor func generatedSequenceActuallyMovesNativeScrollView() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    scrollView.hasVerticalScroller = true
    scrollView.verticalScrollElasticity = .none
    scrollView.horizontalScrollElasticity = .none
    scrollView.documentView = TestScrollDocument(frame: NSRect(x: 0, y: 0, width: 280, height: 3000))
    window.contentView = scrollView
    scrollView.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: .zero)
    let stream = ScrollEventStream()
    #expect(stream.accept(try wheel(y: -12)))
    for event in drain(stream) { scrollView.scrollWheel(with: try #require(NSEvent(cgEvent: event))) }
    let deadline = Date(timeIntervalSinceNow: 0.2)
    while scrollView.contentView.bounds.origin.y < 340 && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    #expect(scrollView.contentView.bounds.origin.y > 340)
    #expect(scrollView.contentView.bounds.origin.y < 380)
}

@Test func temporaryFrameAllocationFailureDoesNotLoseDistance() throws {
    var calls = 0
    let stream = ScrollEventStream(makeEvent: { x, y in
        calls += 1
        if calls == 2 { return nil }
        return CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
    })
    #expect(stream.accept(try wheel()))
    #expect(stream.nextFrame(seconds: 1 / 60) == nil)
    let frames = drain(stream)
    #expect(frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) } == 90)
}

@Test func outputFramesKeepFreshCursorPositionInsteadOfReplayingWheelPosition() throws {
    var currentPointer = CGPoint(x: 800, y: 600)
    let stream = ScrollEventStream(makeEvent: { x, y in
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
        // Emulate the native constructor sampling the current pointer each frame.
        event?.location = currentPointer
        return event
    })
    let input = try wheel(y: 12)
    #expect(input.location == CGPoint(x: 400, y: 300))
    #expect(stream.accept(input))
    let first = try #require(stream.nextFrame(seconds: 1 / 60))
    #expect(first.location == currentPointer)
    currentPointer = CGPoint(x: 1000, y: 720)
    let second = try #require(stream.nextFrame(seconds: 1 / 60))
    #expect(second.location == currentPointer)
    #expect(second.location != input.location)
    #expect(stream.hasPendingFrames)
}

@Test(arguments: [0.3, 0.8, 1.0, 1.2, 3.0])
func fasterBaselineScalesEverySpeedProportionally(speed: Double) throws {
    let stream = ScrollEventStream()
    stream.speed = speed
    #expect(stream.accept(try wheel(y: 10, x: -5)))
    let frames = drain(stream)
    let vertical = frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
    let horizontal = frames.reduce(Int64(0)) { $0 + $1.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) }
    #expect(abs(Double(vertical) - 300 * speed) <= 1)
    #expect(abs(Double(horizontal) + 150 * speed) <= 1)
}
