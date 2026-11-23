// swift-tools-version: 6.0
import PackageDescription

let featureDependencies: [Target.Dependency] = [
    .product(name: "DesignSystem", package: "DesignSystem"),
    .product(name: "SleepDomain", package: "SleepDomain"),
    .product(name: "SleepAnalysis", package: "SleepAnalysis")
]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "DashboardFeature", targets: ["DashboardFeature"]),
        .library(name: "JournalFeature", targets: ["JournalFeature"]),
        .library(name: "NightFeature", targets: ["NightFeature"]),
        .library(name: "StatisticsFeature", targets: ["StatisticsFeature"]),
        .library(name: "InsightsFeature", targets: ["InsightsFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../SleepDomain"),
        .package(path: "../SleepAnalysis")
    ],
    targets: [
        .target(name: "DashboardFeature", dependencies: featureDependencies),
        .target(name: "JournalFeature", dependencies: featureDependencies),
        .target(name: "NightFeature", dependencies: featureDependencies),
        .target(name: "StatisticsFeature", dependencies: featureDependencies),
        .target(name: "InsightsFeature", dependencies: featureDependencies),
        .target(name: "SettingsFeature", dependencies: featureDependencies)
    ]
)
