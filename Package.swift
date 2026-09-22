// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kagami",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kagami", targets: ["Kagami"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "Kagami",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LocalizationTests", dependencies: ["Kagami"], path: "Tests/LocalizationTests"),
        .testTarget(name: "APIKeyTests", dependencies: ["Kagami"], path: "Tests/APIKeyTests")
    ]
)
