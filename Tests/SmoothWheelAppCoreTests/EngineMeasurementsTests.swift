import AppKit
import ScrollEvents
import Testing
@testable import SmoothWheelAppCore

/// Release-only callback microbenchmark. Uses the real coordinator and Quartz
/// packets, but captures output locally: no event tap, permissions or global post.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_MEASURE"] == "1"))
@MainActor func productionCallbackMeasurements() async throws {
    _ = NSApplication.shared
    var now = 10.0, posted = 0
    let registry = ScrollRecipientRegistry(owners: [101: "excluded.chat", 202: "other.window", 909: "background.renderer"])
    let source = try #require(CGEventSource(stateID: .privateState)); source.pixelsPerLine = 10
    let wheel = try #require(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
    wheel.location = CGPoint(x: 200, y: 200)
    var reports: [String: [String: Double]] = [:]
    for (name, owner) in [("nativeCallback", "excluded.chat"), ("smoothCallback", "other.window"), ("backgroundRendererCallback", "background.renderer")] {
        let target = ScrollTargetResolver { _ in
            ScrollTarget(owner: owner, bounds: CGRect(x: -10000, y: -10000, width: 20000, height: 20000))
        }
        let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { _ in posted += 1 }, recipientOwner: registry.owner(for:))
        defer { engine.stop() }
        engine.excluded = ["excluded.chat"]; engine.enabled = true
        try #require(await eventually { target.target(at: wheel.location) != nil })
        wheel.setIntegerValueField(.eventTargetUnixProcessID, value: name == "nativeCallback" ? 101 : (name == "backgroundRendererCallback" ? 909 : 202))
        now += 1
        var samples: [Double] = [], frames: [Double] = []
        for i in 0..<5200 {
            now += 0.002
            let start = ProcessInfo.processInfo.systemUptime
            let native = engine.handle(type: .scrollWheel, event: wheel) != nil
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            #expect(native == (name == "nativeCallback"))
            if i >= 200 { samples.append(elapsed) }
            if i % 4 == 3 {
                let tickStart = ProcessInfo.processInfo.systemUptime
                engine.tick()
                if i >= 200 && name == "smoothCallback" {
                    frames.append((ProcessInfo.processInfo.systemUptime - tickStart) * 1000)
                }
            }
        }
        func summarize(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["samples": Double(sorted.count), "p50Ms": sorted[sorted.count / 2],
                    "p95Ms": sorted[Int(Double(sorted.count - 1) * 0.95)], "maximumMs": sorted.last!]
        }
        reports[name] = summarize(samples)
        if !frames.isEmpty { reports["frameEmission"] = summarize(frames) }
        engine.cancel()
    }
    #expect(posted > 0)
    let destination = repositoryRoot.appendingPathComponent("artifacts/performance")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        .write(to: destination.appendingPathComponent("callbacks.json"))
}
