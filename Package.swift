// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Momentum",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "MomentumCore", targets: ["MomentumCore"])
    ],
    targets: [
        .target(
            name: "MomentumCore",
            path: "Sources/MomentumCore"
        ),
        .testTarget(
            name: "MomentumCoreTests",
            dependencies: ["MomentumCore"],
            path: "Tests/MomentumCoreTests"
        )
    ]
)
