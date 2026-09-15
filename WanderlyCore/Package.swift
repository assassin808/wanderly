// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WanderlyCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "WanderlyCore", targets: ["WanderlyCore"]),
    ],
    targets: [
        .target(name: "WanderlyCore"),
        .testTarget(name: "WanderlyCoreTests", dependencies: ["WanderlyCore"]),
    ]
)
