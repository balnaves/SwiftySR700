// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftySR700",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SwiftySR700",
            targets: ["SwiftySR700"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/yeokm1/SwiftSerial.git", from: "0.1.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftySR700",
            dependencies: ["SwiftSerial", "Logging"]),
        .testTarget(
            name: "SwiftySR700Tests",
            dependencies: ["SwiftySR700"]),
    ]
)
