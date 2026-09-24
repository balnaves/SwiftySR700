// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SR700ArtisanBridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0")
    ],
    targets: [
        // WebSocket server and command line entry point
        .executableTarget(
            name: "SR700ArtisanBridge",
            dependencies: [
                "SR700BridgeCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ]),
        // Artisan protocol, roaster session and simulator, independent of the server
        .target(
            name: "SR700BridgeCore",
            dependencies: [
                .product(name: "SwiftySR700", package: "SwiftySR700"),
                .product(name: "Logging", package: "swift-log")
            ]),
        .testTarget(
            name: "SR700BridgeCoreTests",
            dependencies: ["SR700BridgeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
