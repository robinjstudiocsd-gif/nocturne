// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepAnalysis",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SleepAnalysis", targets: ["SleepAnalysis"])
    ],
    dependencies: [
        .package(path: "../SleepDomain")
    ],
    targets: [
        .target(name: "SleepAnalysis", dependencies: ["SleepDomain"]),
        .testTarget(name: "SleepAnalysisTests", dependencies: ["SleepAnalysis", "SleepDomain"])
    ]
)
