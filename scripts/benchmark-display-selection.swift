import AppKit
import ScrollTiming
let bounds = CGDisplayBounds(CGMainDisplayID())
let clock = ScrollFrameClock()
clock.start(at: CGPoint(x: bounds.midX, y: bounds.midY)) {}
let count = 20000
var samples: [String: [Double]] = ["screenQuery": [], "cachedBounds": []]
var checksum: UInt64 = 0
for _ in 0..<5 {
    var start = DispatchTime.now().uptimeNanoseconds
    for i in 0..<count {
        var display = CGMainDisplayID(), found: UInt32 = 0
        let point = CGPoint(x: bounds.midX + Double(i % 10), y: bounds.midY)
        _ = CGGetDisplaysWithPoint(point, 1, &display, &found)
        checksum += UInt64(found)
    }
    samples["screenQuery"]!.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count))
    start = DispatchTime.now().uptimeNanoseconds
    for i in 0..<count {
        if clock.isTracking(CGPoint(x: bounds.midX + Double(i % 10), y: bounds.midY)) { checksum += 1 }
    }
    samples["cachedBounds"]!.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count))
}
clock.stop()
let report: [String: Any] = ["iterationsPerSample":count,"samplesPerPath":5,"medianScreenQueryNs":samples["screenQuery"]!.sorted()[2],"medianCachedBoundsNs":samples["cachedBounds"]!.sorted()[2],"checksum":checksum]
print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
