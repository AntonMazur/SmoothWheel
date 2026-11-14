import Foundation
import CoreGraphics
import ScrollCore
import ScrollEvents

var traces: [[String: Any]] = []
for smoothing in [0.15, 0.45, 0.8] {
    let stream = ScrollEventStream()
    stream.smoothing = smoothing
    let input = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0)!
    precondition(stream.accept(input))
    var ticks = 0, emptyTicks = 0, pixels: Int64 = 0
    let start = DispatchTime.now().uptimeNanoseconds
    while stream.hasPendingFrames && ticks < 2000 {
        ticks += 1
        if let frame = stream.nextFrame(seconds: 1 / 120) { pixels += frame.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
        else { emptyTicks += 1 }
    }
    traces.append(["smoothing": smoothing,"timerTicks":ticks,"ticksWithoutOutput":emptyTicks,"pixels":pixels,"simulatedDurationMs":Double(ticks)*1000/120,"executionMicroseconds":Double(DispatchTime.now().uptimeNanoseconds-start)/1000])
}
var smoother = ScrollSmoother()
let repetitions = 1_000_000
var checksum: Int64 = 0
let start = DispatchTime.now().uptimeNanoseconds
for index in 0..<repetitions {
    if index % 12 == 0 { smoother.add(90) }
    checksum += Int64(smoother.step(seconds: 1 / 120, smoothing: 0.45))
}
let report: [String:Any] = ["bursts":traces,"coreNanosecondsPerStep":Double(DispatchTime.now().uptimeNanoseconds-start)/Double(repetitions),"checksum":checksum]
let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))
