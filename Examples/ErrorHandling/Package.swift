// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ErrorHandling",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ErrorHandling",
            dependencies: [
                .product(name: "Blend", package: "Blend")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)