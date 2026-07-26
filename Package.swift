// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WetoolsDeveloperTools",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ScrollProbeTest", targets: ["ScrollProbeTest"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "ScrollProbeCore",
            path: "Wetools/Services",
            exclude: [
                "KeychainService.swift",
                "LLMClient.swift",
                "LLMProviderStore.swift",
                "OCRManager.swift",
                "ScreenCaptureScreenshotService.swift",
                "ScrollabilityProbeService.swift"
            ],
            sources: ["ScrollProbeCore.swift"]
        ),
        .executableTarget(
            name: "ScrollProbeTest",
            dependencies: [
                "ScrollProbeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tools/ScrollProbeTest"
        ),
        .testTarget(
            name: "ScrollProbeCoreTests",
            dependencies: ["ScrollProbeCore"],
            path: "Tests/ScrollProbeCoreTests"
        )
    ]
)
