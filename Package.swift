// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Akashica",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Akashica",
            targets: ["Akashica"]
        ),
        .library(
            name: "AkashicaStorage",
            targets: ["AkashicaStorage"]
        ),
    ],
    dependencies: [],
    targets: [
        // Main public API
        .target(
            name: "Akashica",
            dependencies: ["AkashicaCore"]
        ),

        // Storage implementations
        .target(
            name: "AkashicaStorage",
            dependencies: [
                "Akashica",
                "AkashicaCore"
            ]
        ),

        // Internal utilities
        .target(
            name: "AkashicaCore",
            dependencies: []
        ),

        // Tests
        .testTarget(
            name: "AkashicaTests",
            dependencies: ["Akashica"]
        ),
        .testTarget(
            name: "AkashicaStorageTests",
            dependencies: ["AkashicaStorage"]
        ),
        .testTarget(
            name: "AkashicaCoreTests",
            dependencies: ["AkashicaCore"]
        ),
    ]
)
