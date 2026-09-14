// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kagami",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kagami", targets: ["Kagami"])],
    targets: [.executableTarget(name: "Kagami")]
)
