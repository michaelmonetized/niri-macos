// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "niri-macos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "niri-macos", targets: ["niri-macos"]),
        .executable(name: "niri-msg", targets: ["niri-msg"]),
        .library(name: "NiriCore", targets: ["NiriCore"]),
    ],
    targets: [
        .target(
            name: "NiriCore",
            path: "Sources/NiriCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "niri-macos",
            dependencies: ["NiriCore"],
            path: "Sources/niri-macos",
            sources: ["main.swift"]
        ),
        .executableTarget(
            name: "niri-msg",
            path: "Sources/niri-msg",
            sources: ["main.swift"]
        ),
        .testTarget(
            name: "NiriCoreTests",
            dependencies: ["NiriCore"],
            path: "Tests/NiriCoreTests"
        ),
    ]
)
