// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EZCal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "EZCal", path: "Sources/EZCal"),
        .testTarget(name: "EZCalTests", dependencies: ["EZCal"], path: "Tests/EZCalTests"),
    ]
)
