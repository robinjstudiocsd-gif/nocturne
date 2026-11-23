// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NightRecording",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NightRecording", targets: ["NightRecording"])
    ],
    dependencies: [
        .package(path: "../SleepDomain"),
        .package(path: "../SleepAnalysis")
    ],
    targets: [
        .target(name: "NightRecording", dependencies: ["SleepDomain", "SleepAnalysis"]),
        .testTarget(name: "NightRecordingTests", dependencies: ["NightRecording", "SleepDomain", "SleepAnalysis"])
    ]
)
