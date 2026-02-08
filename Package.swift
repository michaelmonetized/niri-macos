// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "niri-macos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "niri-macos", targets: ["niri-macos"]),
        .executable(name: "niri-msg", targets: ["niri-msg"]),
    ],
    targets: [
        .executableTarget(
            name: "niri-macos",
            path: "Sources/niri-macos",
            sources: [
                "main.swift",
                "Logger.swift",
                "Core/Types.swift",
                "Core/AnimationController.swift",
                "Window/WindowEnumerator.swift",
                "Window/WindowController.swift",
                "Window/AXObserver.swift",
                "Layout/LayoutEngine.swift",
                "Input/GestureRecognizer.swift",
                "IPC/IPCServer.swift",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "niri-msg",
            path: "Sources/niri-msg",
            sources: ["main.swift"]
        )
    ]
)
