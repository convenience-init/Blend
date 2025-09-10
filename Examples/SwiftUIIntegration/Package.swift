// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftUIIntegration",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "SwiftUIIntegration",
            dependencies: [
                .product(name: "Blend", package: "Blend")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)