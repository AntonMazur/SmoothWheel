import AppKit
import ScrollEvents
import Testing
@testable import SmoothWheelAppCore

@Test @MainActor func annotatedRecipientSwitchesImmediatelyFromExcludedChatToWindowedMessenger() throws {
    _ = NSApplication.shared
    let registry = ScrollRecipientRegistry(owners: [101: "excluded.chat", 202: "windowed.messenger", 303: "system.overlay"])
    let staleAX = ReplayTarget(); staleAX.set("excluded.chat")
    var now = 1.0, output = 0
    let engine = ScrollEngine(targets: staleAX, uptime: { now }, postEvent: { _ in output += 1 }, recipientOwner: registry.owner(for:))
    defer { engine.stop() }
    engine.excluded = ["excluded.chat"]; engine.enabled = true
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
    event.location = CGPoint(x: 200, y: 200)
    event.setIntegerValueField(.eventTargetUnixProcessID, value: 101)
    #expect(engine.handle(type: .scrollWheel, event: event)?.takeUnretainedValue() === event)
    // Same pointer, overlapping windows, and no burst gap: a new receiver is a
    // new transaction, even when AX still reports the excluded background app.
    for pid: Int64 in [202, 303, 202] {
        now += 0.02
        event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
        #expect(engine.handle(type: .scrollWheel, event: event) == nil)
        now += 1.0 / 120; engine.tick()
    }
    #expect(output == 3)
    event.setIntegerValueField(.eventTargetUnixProcessID, value: 101)
    #expect(engine.handle(type: .scrollWheel, event: event)?.takeUnretainedValue() === event)
    #expect(!engine.isAnimating)
}

@Test @MainActor func annotatedRecipientWorksWithoutAXAndRejectsUnknownProcesses() throws {
    let registry = ScrollRecipientRegistry(owners: [202: "windowed.messenger"])
    let target = ReplayTarget()
    var now = 1.0
    let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { _ in }, recipientOwner: registry.owner(for:))
    defer { engine.stop() }
    engine.excluded = ["excluded.chat"]; engine.enabled = true
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0))
    event.location = CGPoint(x: 200, y: 200)
    event.setIntegerValueField(.eventTargetUnixProcessID, value: 202)
    #expect(engine.handle(type: .scrollWheel, event: event) == nil)
    // A stale AX result cannot steal a burst whose receiver came from the OS.
    target.set("excluded.chat")
    #expect(engine.isAnimating)
    let move = try #require(CGEvent(source: nil))
    move.setIntegerValueField(.eventTargetUnixProcessID, value: 101)
    _ = engine.handle(type: .mouseMoved, event: move)
    #expect(!engine.isAnimating)
    now += 1
    target.set("windowed.messenger")
    event.setIntegerValueField(.eventTargetUnixProcessID, value: 999)
    #expect(engine.handle(type: .scrollWheel, event: event)?.takeUnretainedValue() === event)
    #expect(registry.owner(for: -1) == nil)
    #expect(registry.owner(for: Int64.max) == nil)
}

@Test @MainActor func processIdentityCacheIncludesWorkspaceApplications() throws {
    let app = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier != nil && !$0.isTerminated })
    let registry = ScrollRecipientRegistry()
    #expect(registry.owner(for: Int64(app.processIdentifier)) == app.bundleIdentifier)
}
