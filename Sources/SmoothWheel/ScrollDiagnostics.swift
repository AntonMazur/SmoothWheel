import CoreGraphics
import Foundation

/// Opt-in local diagnostics for development runs. No file is written in normal use.
final class ScrollDiagnostics {
    static func fromEnvironment() -> ScrollDiagnostics? {
        guard let path = ProcessInfo.processInfo.environment["SMOOTHWHEEL_DIAGNOSTICS"], !path.isEmpty else { return nil }
        return ScrollDiagnostics(path: path)
    }
    private let path: String
    private let writer = DispatchQueue(label: "local.smoothwheel.diagnostics", qos: .utility)
    private var flushPending = false
    private var accepted = 0
    private var continuous = 0
    private var frames = 0
    private var maximumPointerMismatch = 0.0
    private var outputPixels = 0
    private var firstLocation: CGPoint?
    private var outputLocationsChanged = false
    private var currentClockMode = "stopped"
    private var frameIntervals: [Double] = []
    private var largestFramePixels: Int64 = 0
    func clockMode(_ mode: String) { currentClockMode = mode }
    func frameInterval(_ interval: Double) {
        if frameIntervals.count < 20000 { frameIntervals.append(interval * 1000) }
    }

    private init(path: String) { self.path = path; flush() }
    func acceptedWheel() { accepted += 1 }
    func bypassed(_ event: CGEvent) {
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { continuous += 1 }
    }
    func output(_ event: CGEvent) {
        frames += 1
        largestFramePixels = max(largestFramePixels, abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
        outputPixels += abs(Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
        if let firstLocation { outputLocationsChanged = outputLocationsChanged || firstLocation != event.location }
        else { firstLocation = event.location }
        if let current = CGEvent(source: nil)?.location {
            maximumPointerMismatch = max(maximumPointerMismatch, hypot(current.x - event.location.x, current.y - event.location.y))
        }
    }
    /// Coalesce requests on the main loop, then sort/encode/write off the input path.
    /// Mutable counters stay on the main thread; the writer receives a value snapshot.
    func flush() {
        precondition(Thread.isMainThread)
        guard !flushPending else { return }
        flushPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.flushPending = false
            let snapshot = Snapshot(path: self.path, accepted: self.accepted, continuous: self.continuous,
                frames: self.frames, maximumPointerMismatch: self.maximumPointerMismatch,
                outputPixels: self.outputPixels, outputLocationsChanged: self.outputLocationsChanged,
                clockMode: self.currentClockMode, intervals: self.frameIntervals,
                largestFramePixels: self.largestFramePixels)
            self.writer.async { snapshot.write() }
        }
    }

    private struct Snapshot: Sendable {
        let path: String
        let accepted: Int
        let continuous: Int
        let frames: Int
        let maximumPointerMismatch: Double
        let outputPixels: Int
        let outputLocationsChanged: Bool
        let clockMode: String
        let intervals: [Double]
        let largestFramePixels: Int64

        func write() {
            let sorted = intervals.sorted()
            let p95 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)]
            let report: [String: Any] = ["acceptedDiscreteEvents": accepted, "bypassedContinuousEvents": continuous,
                "postedFrames": frames, "absoluteVerticalPixels": outputPixels,
                "maximumPointerMismatchPixels": maximumPointerMismatch, "outputLocationsChanged": outputLocationsChanged,
                "clockMode": clockMode, "frameIntervalsRecorded": sorted.count,
                "frameIntervalP95Ms": p95, "frameIntervalMaximumMs": sorted.last ?? 0,
                "largestVerticalFramePixels": largestFramePixels]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }
}
