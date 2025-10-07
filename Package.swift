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
        .library(
            name: "AkashicaS3Storage",
            targets: ["AkashicaS3Storage"]
        ),
        .executable(
            name: "akashica",
            targets: ["AkashicaCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "0.40.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Main public API
        .target(
            name: "Akashica",
            dependencies: ["AkashicaCore"]
        ),

        // Storage implementations (local only)
        .target(
            name: "AkashicaStorage",
            dependencies: [
                "Akashica",
                "AkashicaCore"
            ]
        ),

        // S3 storage adapter (separate to isolate AWS SDK)
        .target(
            name: "AkashicaS3Storage",
            dependencies: [
                "Akashica",
                "AkashicaCore",
                .product(name: "AWSS3", package: "aws-sdk-swift")
            ]
        ),

        // Internal utilities
        .target(
            name: "AkashicaCore",
            dependencies: []
        ),

        // CLI executable
        .executableTarget(
            name: "AkashicaCLI",
            dependencies: [
                "Akashica",
                "AkashicaStorage",
                "AkashicaS3Storage",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),

        // Test support (shared test helpers)
        .target(
            name: "TestSupport",
            dependencies: ["Akashica"],
            path: "Tests/TestSupport"
        ),

        // Tests
        .testTarget(
            name: "AkashicaTests",
            dependencies: ["Akashica", "AkashicaStorage", "TestSupport"]
        ),
        .testTarget(
            name: "AkashicaStorageTests",
            dependencies: ["AkashicaStorage"]
        ),
        .testTarget(
            name: "AkashicaCoreTests",
            dependencies: ["AkashicaCore"]
        ),
        .testTarget(
            name: "AkashicaS3StorageTests",
            dependencies: ["Akashica", "AkashicaS3Storage", "TestSupport"]
        ),
    ]
)
