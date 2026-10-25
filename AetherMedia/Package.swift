// swift-tools-version: 5.10
import PackageDescription

// Core-only package for portable logic tests on macOS. The iOS application and
// AVPlayer integration tests belong to AetherMedia.xcodeproj.
let package = Package(
    name: "AetherMediaCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AetherMedia", targets: ["AetherMedia"])],
    targets: [
        .target(name: "AetherMedia", path: "Sources/AetherMedia", exclude: ["App", "UI", "Services/Playback/PlaybackEngine.swift", "Services/Playback/ExtendedPlaybackController.swift", "Core/Persistence/KeychainExport.swift"]),
        .testTarget(name: "AetherMediaTests", dependencies: ["AetherMedia"], path: "Tests/AetherMediaTests", exclude: ["PlaybackEngineTests.swift", "ExtendedPlaybackTests.swift", "SourceSelectionTests.swift", "Fixtures"])
    ]
)
