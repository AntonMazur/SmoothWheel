import Testing
@testable import ScrollCore

@Test(arguments: [60.0, 120.0, 144.0])
func distanceIsConserved(refreshRate: Double) {
    var smoother = ScrollSmoother()
    smoother.add(120)
    var total = 0
    for _ in 0..<Int(refreshRate * 3) {
        total += Int(smoother.step(seconds: 1 / refreshRate, smoothing: 0.5))
    }
    #expect(abs(total - 120) <= 1)
    #expect(smoother.remaining == 0)
}

@Test func reversalImmediatelyChangesDirection() {
    var smoother = ScrollSmoother()
    smoother.add(200)
    _ = smoother.step(seconds: 1 / 120, smoothing: 0.8)
    smoother.add(-40)
    #expect(smoother.step(seconds: 1 / 120, smoothing: 0.8) < 0)
}

@Test func resetCancelsPendingScroll() {
    var smoother = ScrollSmoother()
    smoother.add(100)
    smoother.reset()
    #expect(smoother.step(seconds: 1 / 60, smoothing: 0.5) == 0)
}

@Test func backlogAndInvalidInputAreBounded() {
    var smoother = ScrollSmoother()
    smoother.add(.infinity)
    #expect(smoother.remaining == 0)
    smoother.add(1_000_000)
    #expect(smoother.remaining == 2400)
    #expect(smoother.step(seconds: 0, smoothing: 0.5) == 0)
}

@Test(arguments: [0.15, 0.45, 0.8])
func subpixelTailFinishesPromptlyWithoutLosingDistance(smoothing: Double) {
    var smoother = ScrollSmoother()
    smoother.add(90)
    var ticks = 0, pixels = 0
    while smoother.remaining != 0 && ticks < 240 {
        pixels += Int(smoother.step(seconds: 1 / 120, smoothing: smoothing))
        ticks += 1
    }
    #expect(pixels == 90)
    // Less than one second even at the softest preset; the old tail took 1.63s.
    #expect(ticks < 120)
    #expect(smoother.remaining == 0)
    #expect(smoother.step(seconds: 1 / 120, smoothing: smoothing) == 0)
}

@Test(arguments: [0.4, 0.6, 1.0, -0.4, -0.6, -1.0, 90.4, -90.4])
func finishingTailRoundsFractionalDistanceOnlyOnce(distance: Double) {
    var smoother = ScrollSmoother()
    smoother.add(distance)
    var pixels = 0
    for _ in 0..<240 { pixels += Int(smoother.step(seconds: 1 / 120, smoothing: 0.45)) }
    #expect(pixels == Int(distance.rounded()))
    #expect(smoother.remaining == 0)
}

@Test func repeatedNotchesDoNotCreateAbruptVelocitySteps() {
    var smoother = ScrollSmoother()
    smoother.add(100)
    var previous = 0, total = 0
    for _ in 0..<12 {
        previous = Int(smoother.step(seconds: 1 / 120, smoothing: 0.45))
        total += previous
    }
    smoother.add(100)
    let next = Int(smoother.step(seconds: 1 / 120, smoothing: 0.45))
    // The old exponential impulse jumped by ~7 px/frame here.
    #expect(next >= 0)
    #expect(next - previous <= 2)
    total += next
    while smoother.remaining != 0 { total += Int(smoother.step(seconds: 1 / 120, smoothing: 0.45)) }
    #expect(total == 200)
}

@Test func delayedFramesDoNotDumpAllPendingDistanceAtOnce() {
    var regular = ScrollSmoother()
    regular.add(500)
    var delayed = regular
    let normalStep = regular.step(seconds: 1 / 30, smoothing: 0.45)
    let lateStep = delayed.step(seconds: 0.2, smoothing: 0.45)
    #expect(lateStep == normalStep)
    #expect(lateStep < 100)
    #expect(delayed.remaining > 400)
}

@Test(arguments: ScrollPreset.allCases)
func presetSettingsRoundTrip(preset: ScrollPreset) {
    #expect(ScrollPreset.matching(speed: preset.speed, smoothing: preset.smoothing) == preset)
    #expect(ScrollPreset.matching(speed: preset.speed, smoothing: 0.6514) == nil)
}

@Test(arguments: [90.0, -90.0, 360.0, -360.0])
func landingHasNoReversePacketsOrLongSinglePixelGaps(distance: Double) {
    var smoother = ScrollSmoother()
    smoother.add(distance)
    var total = 0, silentFrames = 0, landingStarted = false
    for _ in 0..<500 {
        if smoother.remaining == 0 { break }
        if abs(smoother.remaining) <= 3 { landingStarted = true }
        let pixel = smoother.step(seconds: 1 / 120, smoothing: 0.65)
        #expect(Double(pixel) * distance >= 0)
        total += Int(pixel)
        if landingStarted {
            silentFrames = pixel == 0 ? silentFrames + 1 : 0
            #expect(silentFrames <= 3)
        }
    }
    #expect(total == Int(distance))
    #expect(smoother.remaining == 0)
}

@Test func newWheelInputInterruptsLandingWithoutLosingDistance() {
    var smoother = ScrollSmoother()
    smoother.add(90)
    var total = 0
    while abs(smoother.remaining) > 3 { total += Int(smoother.step(seconds: 1 / 120, smoothing: 0.65)) }
    total += Int(smoother.step(seconds: 1 / 120, smoothing: 0.65))
    smoother.add(90)
    for _ in 0..<500 { total += Int(smoother.step(seconds: 1 / 120, smoothing: 0.65)) }
    #expect(total == 180)
    #expect(smoother.remaining == 0)
}

@Test func zeroAxisInputDoesNotRestartLanding() {
    var baseline = ScrollSmoother()
    baseline.add(90)
    while abs(baseline.remaining) > 3 { _ = baseline.step(seconds: 1 / 120, smoothing: 0.65) }
    _ = baseline.step(seconds: 1 / 120, smoothing: 0.65)
    var withZeroInput = baseline
    for _ in 0..<30 {
        withZeroInput.add(0)
        #expect(withZeroInput.step(seconds: 1 / 120, smoothing: 0.65) == baseline.step(seconds: 1 / 120, smoothing: 0.65))
    }
    #expect(withZeroInput.remaining == 0)
}
