import AppKit
import ScrollEvents
import Testing
@testable import SmoothWheelAppCore

final class ReplayTarget: ScrollTargetProviding {
    var current: ScrollTarget?
    var onChange: ((ScrollTarget?) -> Void)?
    var onProbe: ((Double, Bool) -> Void)?
    func start(at point: CGPoint) {}
    func stop() {}
    func target(at point: CGPoint) -> ScrollTarget? { current }
    func invalidate(at point: CGPoint) { current = nil; onChange?(nil) }
    func request(at point: CGPoint) {}
    func set(_ owner: String?) {
        current = owner.map { ScrollTarget(owner: $0, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000)) }
        onChange?(current)
    }
}

private struct Packet: Codable, Equatable {
    let x: Int64
    let y: Int64
    let precise: Int64
    let phase: Int64
    let momentum: Int64
    let marked: Bool
    init(_ event: CGEvent) {
        x = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        y = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        precise = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        marked = event.getIntegerValueField(.eventSourceUserData) == ScrollEventStream.marker
    }
}
private struct ReplaySnapshot: Codable {
    let decisions: [String]
    let frames: [Packet]
    let totalY: Int64
    let stopped: Bool
}

@Test @MainActor func productionCoordinatorRoutingAndFrameSnapshots() throws {
    _ = NSApplication.shared
    let target = ReplayTarget()
    var now = 10.0
    var output: [Packet] = []
    let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { output.append(Packet($0)) })
    defer { engine.stop() }
    engine.excluded = ["excluded.chat"]
    engine.speed = 1; engine.smoothing = 0.45; engine.enabled = true
    var decisions: [String] = []
    func wheel() throws {
        let source = try #require(CGEventSource(stateID: .privateState)); source.pixelsPerLine = 10
        let event = try #require(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
        event.location = CGPoint(x: 200, y: 200)
        let before = Packet(event)
        if let returned = engine.handle(type: .scrollWheel, event: event) {
            #expect(returned.takeUnretainedValue() === event)
            #expect(Packet(event) == before) // Native exclusion must preserve every delta/phase.
            decisions.append("native")
        } else { decisions.append("smooth") }
    }
    func drain() {
        for _ in 0..<1000 {
            guard engine.isAnimating else { return }
            now += 1.0 / 120; engine.tick()
        }
        Issue.record("Coordinator failed to stop its frame clock")
    }
    target.set("excluded.chat"); try wheel()
    #expect(!engine.isAnimating)
    target.set("system.launcher"); now += 1; try wheel(); drain()
    target.set(nil); now += 1; try wheel()
    target.set("messenger.window"); now += 0.02; try wheel() // Late result: keep native burst native.
    now += 1; try wheel(); drain()
    target.set("excluded.chat"); now += 1; try wheel(); drain()
    #expect(decisions == ["native", "smooth", "native", "native", "smooth", "native"])
    #expect(output.reduce(Int64(0)) { $0 + $1.y } == -180)
    try assertJSONSnapshot(ReplaySnapshot(decisions: decisions, frames: output,
        totalY: output.reduce(0) { $0 + $1.y }, stopped: !engine.isAnimating), name: "engine-routing-and-frames")
}

@Test @MainActor func productionCoordinatorCancelsTailOnTargetBoundaryAndPassesShortcuts() throws {
    let target = ReplayTarget(); target.set("messenger.window")
    var now = 1.0; var output = 0
    let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { _ in output += 1 })
    defer { engine.stop() }
    engine.excluded = ["excluded.chat"]; engine.enabled = true
    let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 10, wheel2: 0, wheel3: 0))
    wheel.location = CGPoint(x: 200, y: 200)
    #expect(engine.handle(type: .scrollWheel, event: wheel) == nil)
    now += 1.0 / 120; engine.tick(); #expect(output > 0)
    target.set("excluded.chat")
    #expect(!engine.isAnimating)
    let count = output; now += 0.1; engine.tick(); #expect(output == count)
    wheel.flags = .maskAlternate
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
    engine.enabled = false
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
}

@Test @MainActor func productionCoordinatorKeepsEmittingDuringBlockedTargetLookup() async throws {
    _ = NSApplication.shared
    let blockNext = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let resolver = ScrollTargetResolver { _ in
        if blockNext.wait(timeout: .now()) == .success {
            started.signal(); _ = release.wait(timeout: .now() + 2)
        }
        return ScrollTarget(owner: "windowed.messenger", bounds: CGRect(x: -10000, y: -10000, width: 20000, height: 20000))
    }
    var now = 1.0, frames = 0
    let engine = ScrollEngine(targets: resolver, uptime: { now += 1.0 / 120; return now }, postEvent: { _ in frames += 1 })
    defer { release.signal(); engine.stop() }
    engine.excluded = ["excluded.chat"]; engine.enabled = true
    let point = CGPoint(x: 200, y: 200)
    try #require(await eventually { resolver.target(at: point) != nil })
    let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
    wheel.location = point
    blockNext.signal()
    #expect(engine.handle(type: .scrollWheel, event: wheel) == nil)
    try #require(await eventually { started.wait(timeout: .now()) == .success })
    let before = frames
    #expect(await eventually { frames >= before + 3 })
    // Invalidation must end that tail; the late completion must not transform a
    // partially native burst into smoothed input in a system overlay.
    resolver.invalidate(at: point)
    #expect(!engine.isAnimating)
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
    release.signal()
    try #require(await eventually { resolver.target(at: point) != nil })
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
}

@MainActor func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while ProcessInfo.processInfo.systemUptime < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@Test @MainActor func productionCoordinatorInterruptionsDoNotLeakMotion() throws {
    let target = ReplayTarget(); target.set("other.window")
    var now = 1.0, posts = 0
    let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { _ in posts += 1 })
    defer { engine.stop() }
    engine.enabled = true
    let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
    wheel.location = CGPoint(x: 200, y: 200)
    for kind: CGEventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .flagsChanged, .tapDisabledByTimeout, .tapDisabledByUserInput] {
        now += 1
        #expect(engine.handle(type: .scrollWheel, event: wheel) == nil)
        let interruption = try #require(CGEvent(source: nil)); interruption.flags = .maskShift
        _ = engine.handle(type: kind, event: interruption)
        #expect(!engine.isAnimating)
    }
    #expect(posts == 0)
    #expect(engine.handle(type: .scrollWheel, event: wheel) == nil)
    now += 1 // Suspension discards pending distance rather than posting a jump.
    engine.tick(); #expect(posts == 0); #expect(!engine.isAnimating)
    wheel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
    wheel.setIntegerValueField(.eventSourceUserData, value: ScrollEventStream.marker)
    #expect(engine.handle(type: .scrollWheel, event: wheel)?.takeUnretainedValue() === wheel)
}
