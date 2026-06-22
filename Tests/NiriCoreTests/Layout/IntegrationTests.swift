import XCTest
import CoreGraphics
@testable import NiriCore

final class IntegrationTests: XCTestCase {

    // MARK: - Dual Monitor Isolation

    func testDualMonitorIsolation() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Add a second monitor to the right
        let monitor2 = Monitor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        engine.monitors.append(monitor2)

        // Add window 100 to monitor 0's workspace
        engine.windowRegistry[100] = makeWindowInfo(id: 100)
        engine.addWindowToWorkspace(100, monitor: 0)

        // Add window 200 to monitor 1's workspace
        engine.windowRegistry[200] = makeWindowInfo(id: 200)
        engine.addWindowToWorkspace(200, monitor: 1)

        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 1)
        XCTAssertEqual(engine.monitors[1].activeWorkspace.columns.count, 1)
        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns[0].windowIDs, [100])
        XCTAssertEqual(engine.monitors[1].activeWorkspace.columns[0].windowIDs, [200])

        // Focus left on monitor 0 -- should not affect monitor 1
        engine.activeMonitorOverride = 0
        engine.focusColumnLeft()

        // Monitor 1 still has its window and column
        XCTAssertEqual(engine.monitors[1].activeWorkspace.columns.count, 1)
        XCTAssertEqual(engine.monitors[1].activeWorkspace.columns[0].windowIDs, [200])

        // Operations on monitor 1 should not touch monitor 0
        engine.activeMonitorOverride = 1
        engine.windowRegistry[300] = makeWindowInfo(id: 300)
        engine.addWindowToWorkspace(300, monitor: 1)

        XCTAssertEqual(
            engine.monitors[0].activeWorkspace.columns.count, 1,
            "Adding a window to monitor 1 must not change monitor 0's column count"
        )
        XCTAssertEqual(engine.monitors[1].activeWorkspace.columns.count, 2)
    }

    // MARK: - Window Lifecycle

    func testWindowLifecycle() {
        let (engine, _, enumerator, _) = LayoutEngine.makeForTesting()

        enumerator.windows = [
            makeWindowInfo(id: 100),
            makeWindowInfo(id: 200),
            makeWindowInfo(id: 300),
        ]

        engine.addWindow(100)
        engine.addWindow(200)
        engine.addWindow(300)

        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 3)
        XCTAssertEqual(engine.windowRegistry.count, 3)

        // Remove the middle window
        engine.removeWindow(200)

        let columns = engine.monitors[0].activeWorkspace.columns
        XCTAssertEqual(columns.count, 2, "After removing 200, two columns should remain")

        let allIDs = columns.flatMap(\.windowIDs)
        XCTAssertTrue(allIDs.contains(100))
        XCTAssertTrue(allIDs.contains(300))
        XCTAssertFalse(allIDs.contains(200))
        XCTAssertEqual(engine.windowRegistry.count, 2)
    }

    // MARK: - Complex Workflow

    func testComplexWorkflow() {
        let (engine, _, enumerator, _) = LayoutEngine.makeForTesting()

        // Step 1: Add three windows (each in its own column)
        enumerator.windows = [
            makeWindowInfo(id: 100),
            makeWindowInfo(id: 200),
            makeWindowInfo(id: 300),
        ]
        engine.addWindow(100)
        engine.addWindow(200)
        engine.addWindow(300)

        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 3)

        // Step 2: Move the focused column left
        // After adding 300, focus is on the last-inserted column.
        // moveColumnLeft swaps the focused column with the one to its left.
        let focusBefore = engine.monitors[0].activeWorkspace.focusedColumnIndex
        if focusBefore > 0 {
            engine.moveColumnLeft()
            XCTAssertEqual(
                engine.monitors[0].activeWorkspace.focusedColumnIndex,
                focusBefore - 1,
                "focusedColumnIndex should decrease by 1 after moveColumnLeft"
            )
        }

        // Step 3: Consume a window from the next column into the current one
        let colCountBefore = engine.monitors[0].activeWorkspace.columns.count
        let focusedIdx = engine.monitors[0].activeWorkspace.focusedColumnIndex
        if focusedIdx < colCountBefore - 1 {
            engine.consumeWindowIntoColumn()
            // The next column's window should have been absorbed
            XCTAssertTrue(
                engine.monitors[0].activeWorkspace.columns.count < colCountBefore,
                "Consuming should reduce column count when next column becomes empty"
            )
        }

        // Step 4: Switch workspace
        engine.workspaceDown()
        XCTAssertEqual(
            engine.monitors[0].activeWorkspaceIndex, 1,
            "workspaceDown should switch to workspace index 1"
        )

        // The new workspace should be empty
        XCTAssertTrue(engine.monitors[0].activeWorkspace.columns.isEmpty)

        // Go back to workspace 0 and verify windows are still there
        engine.workspaceUp()
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)
        XCTAssertFalse(engine.monitors[0].activeWorkspace.columns.isEmpty)
    }

    // MARK: - Add / Remove / Add

    func testAddRemoveAddWindow() {
        let (engine, _, enumerator, _) = LayoutEngine.makeForTesting()

        // Add window 100
        enumerator.windows = [makeWindowInfo(id: 100)]
        engine.addWindow(100)
        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 1)
        XCTAssertNotNil(engine.windowRegistry[100])

        // Remove window 100
        engine.removeWindow(100)
        XCTAssertTrue(engine.monitors[0].activeWorkspace.columns.isEmpty)
        XCTAssertNil(engine.windowRegistry[100])

        // Add a different window 200
        enumerator.windows = [makeWindowInfo(id: 200)]
        engine.addWindow(200)

        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 1)
        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns[0].windowIDs, [200])
        XCTAssertNotNil(engine.windowRegistry[200])
        XCTAssertNil(engine.windowRegistry[100], "Window 100 should still be absent after adding 200")
    }
}
