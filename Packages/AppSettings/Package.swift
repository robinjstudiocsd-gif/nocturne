// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppSettings",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppSettings", targets: ["AppSettings"])
    ],
    dependencies: [
        .package(path: "../SleepDomain")
    ],
    targets: [
        .target(name: "AppSettings", dependencies: ["SleepDomain"]),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings", "SleepDomain"])
    ]
)
