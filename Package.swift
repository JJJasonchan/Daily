// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Daily",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DailyCore", targets: ["DailyCore"]),
        .executable(name: "Daily", targets: ["DailyApp"])
    ],
    targets: [
        .target(name: "DailyCore"),
        .executableTarget(name: "DailyApp", dependencies: ["DailyCore"], exclude: ["Resources"]),
        .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"]),
        .testTarget(name: "DailyAppTests", dependencies: ["DailyApp", "DailyCore"])
    ]
)
