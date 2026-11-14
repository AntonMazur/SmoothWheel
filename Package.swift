// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SmoothWheel", platforms: [.macOS(.v13)],
    products: [.executable(name: "SmoothWheel", targets: ["SmoothWheel"])],
    targets: [
        .target(name: "ScrollCore"),
        .target(name: "ScrollTiming"),
        .target(name: "ScrollEvents", dependencies: ["ScrollCore"]),
        .executableTarget(name: "SmoothWheel", dependencies: ["ScrollCore", "ScrollEvents", "ScrollTiming"]),
        .testTarget(name: "ScrollTimingTests", dependencies: ["ScrollTiming"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
        .testTarget(name: "ScrollEventsTests", dependencies: ["ScrollEvents"])
    ]
)
