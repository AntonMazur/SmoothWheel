import Foundation
import Testing

let testRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryRoot = testRoot.deletingLastPathComponent().deletingLastPathComponent()
let artifactsRoot = repositoryRoot.appendingPathComponent("artifacts/tests")

func assertJSONSnapshot<T: Encodable>(_ value: T, name: String) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value) + Data([10])
    let expected = testRoot.appendingPathComponent("Snapshots/\(name).json")
    try FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)
    try data.write(to: artifactsRoot.appendingPathComponent("\(name).actual.json"))
    if ProcessInfo.processInfo.environment["SMOOTHWHEEL_RECORD_SNAPSHOTS"] == "1" {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            Issue.record("Snapshot recording is forbidden in CI"); return
        }
        try data.write(to: expected)
    }
    guard FileManager.default.fileExists(atPath: expected.path) else {
        Issue.record("Missing layout baseline: \(name). Review the recorded actual layout.")
        return
    }
    let baseline = try Data(contentsOf: expected)
    #expect(data == baseline, "Snapshot changed: \(name). Inspect artifacts/tests before explicitly recording a new baseline.")
}
