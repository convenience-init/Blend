// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Blend",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Blend",
            targets: ["Blend"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Blend",
            dependencies: [],
            resources: [
                .process("Infrastructure/Resources")
            ]
        ),
        .testTarget(
            name: "BlendTests",
            dependencies: ["Blend"]
        ),
    ]
)
