// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AdvancedNetworking",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "AdvancedNetworking",
            dependencies: [
                .product(name: "Blend", package: "Blend")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
