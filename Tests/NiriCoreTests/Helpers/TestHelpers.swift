import Foundation
import CoreGraphics
@testable import NiriCore

extension LayoutEngine {
    /// Create a LayoutEngine for testing with mocks and a single monitor
    static func makeForTesting(
        monitorFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
        config: LayoutConfig = LayoutConfig(),
        mockController: MockWindowController = MockWindowController(),
        mockEnumerator: MockWindowEnumerator = MockWindowEnumerator(),
        mockLogger: MockLogger = MockLogger()
    ) -> (engine: LayoutEngine, controller: MockWindowController, enumerator: MockWindowEnumerator, logger: MockLogger) {
        let engine = LayoutEngine(
            logger: mockLogger,
            windowEnumerator: mockEnumerator,
            windowController: mockController
        )
        engine.config = config
        engine.activeMonitorOverride = 0
        engine.animationEnabled = false

        // Add a monitor manually
        let monitor = Monitor(displayID: 1, frame: monitorFrame)
        engine.monitors = [monitor]

        return (engine, mockController, mockEnumerator, mockLogger)
    }
}

func makeWindowInfo(id: WindowID, app: String = "TestApp", title: String = "") -> WindowInfo {
    WindowInfo(
        id: id,
        ownerPID: 1234,
        bundleID: "com.test.\(app)",
        appName: app,
        title: title,
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        space: -1,
        isOnScreen: true,
        isMinimized: false,
        layer: 0
    )
}
