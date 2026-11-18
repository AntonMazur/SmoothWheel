import Foundation
import AppKit
import ScrollTiming
import Testing
@testable import ScrollEvents

private let chatTarget = ScrollTarget(owner: "chat", bounds: CGRect(x: 0, y: 0, width: 500, height: 500))
private let otherTarget = ScrollTarget(owner: "messenger", bounds: CGRect(x: 600, y: 0, width: 300, height: 500))

@Test @MainActor func displayFramesContinueWhileTargetProcessIsUnresponsive() async {
    _ = NSApplication.shared
    let gate = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    let resolver = ScrollTargetResolver { _ in
        started.signal()
        _ = gate.wait(timeout: .now() + 2)
        return chatTarget
    }
    let clock = ScrollFrameClock()
    var frames = 0
    resolver.start(at: CGPoint(x: 10, y: 10))
    #expect(await waitFor { started.wait(timeout: .now()) == .success })
    clock.start(at: .zero) { frames += 1 }
    // The target worker is still waiting; the real display clock must keep ticking.
    #expect(await waitFor { frames >= 3 })
    clock.stop(); resolver.stop(); gate.signal()
}

@Test func inactiveExcludedWindowIsNativeAndOtherWindowIsSmooth() {
    var routing = ScrollRoutingState()
    #expect(routing.decide(target: chatTarget, excluded: ["chat"], time: 0).mode == .native)
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 1).mode == .smooth)
}
@Test func lateResolutionCannotMixRawAndSmoothEventsInOneBurst() {
    var routing = ScrollRoutingState()
    #expect(routing.decide(target: nil, excluded: ["chat"], time: 0).mode == .native)
    for time in [0.02, 0.04, 0.08, 0.12] {
        #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: time).mode == .native)
    }
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 0.4).mode == .smooth)
}
@Test func enteringExcludedWindowCancelsPreviousMotionImmediately() {
    var routing = ScrollRoutingState()
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 0).mode == .smooth)
    let boundary = routing.decide(target: chatTarget, excluded: ["chat"], time: 0.01)
    #expect(boundary.mode == .native)
    #expect(boundary.resetMotion)
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 0.02).mode == .native)
}
@Test func allocationFailureKeepsRestOfBurstNative() {
    var routing = ScrollRoutingState()
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 0).mode == .smooth)
    routing.useNativeForBurst()
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 0.02).mode == .native)
    #expect(routing.decide(target: otherTarget, excluded: ["chat"], time: 1).mode == .smooth)
}
@Test func noExclusionsNeedNoTargetLookupAndRepeatedInputKeepsMotion() {
    var routing = ScrollRoutingState()
    #expect(routing.decide(target: nil, excluded: [], time: 0).mode == .smooth)
    #expect(!routing.decide(target: nil, excluded: [], time: 0.01).resetMotion)
    routing.reset()
    #expect(routing.decide(target: chatTarget, excluded: ["chat"], time: 0.02).mode == .native)
}

@MainActor private func waitFor(_ condition: () -> Bool) async -> Bool {
    let deadline = Date(timeIntervalSinceNow: 2)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@Test @MainActor func slowLookupDoesNotBlockInputAndStaleResultsCannotWin() async {
    let gate = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    let resolver = ScrollTargetResolver { point in
        started.signal()
        _ = gate.wait(timeout: .now() + 1)
        return ScrollTarget(owner: point.x < 500 ? "old" : "new", bounds: CGRect(x: point.x, y: 0, width: 100, height: 100))
    }
    var owners: [String] = []
    resolver.onChange = { if let owner = $0?.owner { owners.append(owner) } }
    resolver.start(at: CGPoint(x: 10, y: 10))
    // Let the first request enter the worker. The main actor remains available.
    #expect(await waitFor { started.wait(timeout: .now()) == .success })
    resolver.invalidate(at: CGPoint(x: 600, y: 10))
    #expect(resolver.target(at: CGPoint(x: 10, y: 10)) == nil)
    gate.signal(); gate.signal()
    #expect(await waitFor { resolver.target(at: CGPoint(x: 600, y: 10))?.owner == "new" })
    #expect(!owners.contains("old"))
    resolver.stop()
    #expect(resolver.target(at: CGPoint(x: 600, y: 10)) == nil)
}

@Test @MainActor func resolverKeepsValidSnapshotAcrossTransientFailuresAndStopsCleanly() async {
    // Outside the app rectangle the probe fails, while a still-valid in-window
    // snapshot can be read synchronously without waiting on the worker.
    let failNext = DispatchSemaphore(value: 0)
    let failed = DispatchSemaphore(value: 0)
    let resolver = ScrollTargetResolver { point in
        if failNext.wait(timeout: .now()) == .success {
            failed.signal(); return nil
        }
        return point.x < 500 ? chatTarget : nil
    }
    resolver.start(at: CGPoint(x: 10, y: 10))
    #expect(await waitFor { resolver.target(at: CGPoint(x: 10, y: 10)) != nil })
    failNext.signal()
    resolver.request(at: CGPoint(x: 10, y: 10))
    #expect(await waitFor { failed.wait(timeout: .now()) == .success })
    #expect(resolver.target(at: CGPoint(x: 10, y: 10))?.owner == "chat")
    for x in 10..<400 { resolver.request(at: CGPoint(x: x, y: 10)) }
    #expect(resolver.target(at: CGPoint(x: 100, y: 10))?.owner == "chat")
    resolver.request(at: CGPoint(x: 700, y: 10))
    #expect(resolver.target(at: CGPoint(x: 700, y: 10)) == nil)
    resolver.stop()
    try? await Task.sleep(for: .milliseconds(60))
    #expect(resolver.target(at: CGPoint(x: 10, y: 10)) == nil)
}
