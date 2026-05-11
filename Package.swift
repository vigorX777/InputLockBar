// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InputLockBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "InputLockCore",
            targets: ["InputLockCore"]
        ),
        .executable(
            name: "InputLockCoreHarness",
            targets: ["InputLockCoreHarness"]
        ),
        .executable(
            name: "InputLockBar",
            targets: ["InputLockBar"]
        ),
    ],
    targets: [
        .target(
            name: "InputLockCore"
        ),
        .executableTarget(
            name: "InputLockCoreHarness",
            dependencies: ["InputLockCore"]
        ),
        .executableTarget(
            name: "InputLockBar",
            dependencies: ["InputLockCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
