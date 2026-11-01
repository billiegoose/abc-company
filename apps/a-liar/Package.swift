// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "APPLEPIE",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ALIAR", targets: ["ALIAR"]),
        .library(name: "ALIARCore", targets: ["ALIARCore"]),
    ],
    targets: [
        .target(name: "ALIARCore"),
        .executableTarget(name: "ALIAR", dependencies: ["ALIARCore"]),
        .testTarget(name: "ALIARCoreTests", dependencies: ["ALIARCore"]),
    ]
)
