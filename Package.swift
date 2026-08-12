// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Daily",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DailyCore", targets: ["DailyCore"]),
        .executable(name: "Daily", targets: ["DailyApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "DailyCore"),
        .executableTarget(
            name: "DailyApp",
            dependencies: [
                "DailyCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["Resources"]
        ),
        .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"]),
        .testTarget(name: "DailyAppTests", dependencies: ["DailyApp", "DailyCore"])
    ]
)
