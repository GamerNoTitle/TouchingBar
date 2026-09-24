// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TouchingBar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TouchingBar", targets: ["TouchingBar"]),
        .executable(name: "TouchingBarCtl", targets: ["TouchingBarCtl"]),
        .executable(name: "TouchingBarChecks", targets: ["TouchingBarChecks"]),
        .library(name: "TouchingBarCore", targets: ["TouchingBarCore"])
    ],
    targets: [
        .target(
            name: "TouchingBarDFR",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TouchingBarMediaRemote",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TouchingBarSystemMetrics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TouchingBarCore"
        ),
        .executableTarget(
            name: "TouchingBar",
            dependencies: ["TouchingBarCore", "TouchingBarDFR", "TouchingBarMediaRemote", "TouchingBarSystemMetrics"]
        ),
        .executableTarget(
            name: "TouchingBarCtl",
            dependencies: ["TouchingBarCore", "TouchingBarSystemMetrics"]
        ),
        .executableTarget(
            name: "TouchingBarChecks",
            dependencies: ["TouchingBarCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
