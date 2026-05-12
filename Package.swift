// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "diarize",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "diarize", targets: ["DiarizeCLI"]),
        .executable(name: "diarize-app", targets: ["DiarizeApp"]),
        .library(name: "DiarizeCore", targets: ["DiarizeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.5"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "DiarizeCLI",
            dependencies: [
                "DiarizeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/DiarizeCLI"
        ),
        .executableTarget(
            name: "DiarizeApp",
            dependencies: ["DiarizeCore"],
            path: "Sources/DiarizeApp"
        ),
        .target(
            name: "DiarizeCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/DiarizeCore"
        ),
        .testTarget(
            name: "DiarizeCoreTests",
            dependencies: ["DiarizeCore"],
            path: "Tests/DiarizeCoreTests"
        ),
    ]
)
