import AppKit
import ScrollEvents
import Testing
@testable import SmoothWheelAppCore

@Test @MainActor func registeredBackgroundRendererUsesTheSameSmoothingAndDirectionAsTheSidebar() throws {
    _ = NSApplication.shared
    // Background services must be retained in the same identity cache as UI apps.
    let registry = ScrollRecipientRegistry(owners: [101: "host.notes", 909: "background.renderer"])
    var now = 1.0, output: [Int64] = []
    let engine = ScrollEngine(targets: ReplayTarget(), uptime: { now }, postEvent: {
        output.append($0.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
    }, recipientOwner: registry.owner(for:))
    defer { engine.stop() }
    engine.excluded = ["excluded.chat"]; engine.reversed = true; engine.enabled = true
    let source = try #require(CGEventSource(stateID: .privateState)); source.pixelsPerLine = 10
    let event = try #require(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
    event.location = CGPoint(x: 200, y: 200)
    var totals: [Int64] = []
    for pid: Int64 in [101, 909] {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
        now += 1
        #expect(engine.handle(type: .scrollWheel, event: event) == nil)
        let start = output.count
        for _ in 0..<1000 where engine.isAnimating { now += 1.0 / 120; engine.tick() }
        let frames = Array(output.dropFirst(start))
        #expect(!frames.isEmpty && frames.allSatisfy { $0 > 0 })
        totals.append(frames.reduce(0, +))
    }
    #expect(totals == [90, 90])
}
