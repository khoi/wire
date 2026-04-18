// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "wire",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "wire", targets: ["wire"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "wire",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "wireTests",
            dependencies: ["wire"]
        ),
    ]
)
