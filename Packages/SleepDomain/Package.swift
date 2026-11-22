// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepDomain",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SleepDomain", targets: ["SleepDomain"])
    ],
    targets: [
        .target(name: "SleepDomain"),
        .testTarget(name: "SleepDomainTests", dependencies: ["SleepDomain"])
    ]
)
