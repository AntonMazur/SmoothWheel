import AppKit
import Testing
import ScrollTiming

@Test @MainActor func nativeFrameClockTicksStopsAndRestarts() throws {
    _ = NSApplication.shared
    #expect(!NSScreen.screens.isEmpty)
    let clock = ScrollFrameClock()
    var frames = 0
    clock.start(at: .zero) { frames += 1 }
    #expect(clock.isRunning)
    if #available(macOS 14.0, *) { #expect(clock.mode == "displayLink") }
    let deadline = Date(timeIntervalSinceNow: 1)
    while frames < 3 && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
    #expect(frames >= 3)
    let bounds = CGDisplayBounds(CGMainDisplayID())
    let inside = CGPoint(x: bounds.midX, y: bounds.midY)
    #expect(clock.isTracking(inside))
    clock.start(at: inside) { frames += 10000 }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
    #expect(frames < 10000) // Same-screen input must preserve the existing clock/handler.
    #expect(!clock.isTracking(CGPoint(x: bounds.maxX + 100000, y: bounds.maxY + 100000)))
    clock.stop()
    #expect(!clock.isRunning)
    #expect(!clock.isTracking(inside))
    let stoppedCount = frames
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    #expect(frames == stoppedCount)
    clock.start(at: .zero) { frames += 1 }
    let restartDeadline = Date(timeIntervalSinceNow: 1)
    while frames == stoppedCount && Date() < restartDeadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
    clock.stop()
    #expect(frames > stoppedCount)
}
