// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncNet",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AsyncNet",
            targets: ["AsyncNet"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AsyncNet",
            dependencies: [],
            swiftSettings: [
                .define("MACOS15", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "AsyncNetTests",
            dependencies: ["AsyncNet"],
            swiftSettings: [
                .define("MACOS15", .when(platforms: [.macOS]))
            ]
        ),
    ]
)
