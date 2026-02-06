// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "niri-macos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "niri-macos", targets: ["niri-macos"]),
    ],
    targets: [
        .executableTarget(
            name: "niri-macos",
            path: "Sources/niri-macos",
            sources: [
                "main.swift",
                "Logger.swift",
                "Core/Types.swift",
                "Window/WindowEnumerator.swift",
                "Window/WindowController.swift",
                "Layout/LayoutEngine.swift",
                "IPC/IPCServer.swift",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
