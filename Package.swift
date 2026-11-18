// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SmoothWheel", platforms: [.macOS(.v13)],
    products: [.executable(name: "SmoothWheel", targets: ["SmoothWheel"])],
    targets: [
        .target(name: "ScrollCore"),
        .target(name: "ScrollTiming"),
        .target(name: "ScrollEvents", dependencies: ["ScrollCore"]),
        .target(name: "SmoothWheelAppCore", dependencies: ["ScrollCore", "ScrollEvents", "ScrollTiming"]),
        .executableTarget(name: "SmoothWheel", dependencies: ["SmoothWheelAppCore"]),
        .testTarget(name: "SmoothWheelAppCoreTests", dependencies: ["SmoothWheelAppCore", "ScrollEvents", "ScrollCore"], exclude: ["Snapshots", "Fixtures"]),
        .testTarget(name: "ScrollTimingTests", dependencies: ["ScrollTiming"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
        .testTarget(name: "ScrollEventsTests", dependencies: ["ScrollEvents", "ScrollTiming"])
    ]
)
