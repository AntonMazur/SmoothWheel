import AppKit
import Testing
@testable import SmoothWheelAppCore

@Test @MainActor func diagnosticsCoalesceWritesAndRetainRoutingAndLatencyMeasurements() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("smoothwheel-diagnostics-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: path) }
    let diagnostics = ScrollDiagnostics(path: path.path)
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 5, wheel2: 0, wheel3: 0))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    diagnostics.bypassed(event); diagnostics.output(event)
    event.location = CGPoint(x: -1, y: -1); diagnostics.output(event)
    diagnostics.clockMode("displayLink")
    diagnostics.destination(processID: 202, ownerResolved: true)
    diagnostics.destination(processID: 999, ownerResolved: false)
    diagnostics.destination(processID: 0, ownerResolved: false)
    for _ in 0..<500 {
        diagnostics.acceptedWheel(); diagnostics.route(owner: "excluded.chat", bypass: true)
        diagnostics.inputDuration(0.0002); diagnostics.frameInterval(1.0 / 120)
        diagnostics.flush()
    }
    diagnostics.route(owner: "system.overlay", bypass: false)
    diagnostics.targetProbe(seconds: 0.25, succeeded: false)
    diagnostics.targetProbe(seconds: 0.01, succeeded: true)
    #expect(await eventually { FileManager.default.fileExists(atPath: path.path) })
    let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    #expect(report["acceptedDiscreteEvents"] as? Int == 500)
    #expect(report["postedFrames"] as? Int == 2)
    #expect(report["bypassedContinuousEvents"] as? Int == 1)
    #expect(report["wheelRouting"] as? [String: Int] == ["native:excluded.chat": 500, "smooth:system.overlay": 1])
    #expect(report["inputCallbackP95Ms"] as? Double == 0.2)
    #expect(report["targetProbeMaximumMs"] as? Double == 250)
    #expect(report["failedTargetProbes"] as? Int == 1)
    #expect(report["outputLocationsChanged"] as? Bool == true)
    #expect(report["annotatedDestinationEvents"] as? Int == 1)
    #expect(report["unknownDestinationEvents"] as? Int == 1)
    #expect(report["fallbackDestinationEvents"] as? Int == 1)
    #expect(report["unresolvedRecipientPIDs"] as? [String: Int] == ["999": 1, "0": 1])
}
