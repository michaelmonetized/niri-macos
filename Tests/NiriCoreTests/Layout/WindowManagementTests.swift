import XCTest
import CoreGraphics
@testable import NiriCore

final class WindowManagementTests: XCTestCase {

    // MARK: - Remove Window

    func testRemoveWindow() {
        let (engine, _, enumerator, _) = LayoutEngine.makeForTesting()

        // Add 3 windows via the public API
        enumerator.windows = [
            makeWindowInfo(id: 100),
            makeWindowInfo(id: 200),
            makeWindowInfo(id: 300),
        ]
        engine.addWindow(100)
        engine.addWindow(200)
        engine.addWindow(300)

        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 3)

        // Remove the middle window
        engine.removeWindow(200)

        let columns = engine.monitors[0].activeWorkspace.columns
        XCTAssertEqual(columns.count, 2, "Removing the middle window should leave 2 columns")

        let remainingIDs = columns.flatMap(\.windowIDs)
        XCTAssertTrue(remainingIDs.contains(100))
        XCTAssertTrue(remainingIDs.contains(300))
        XCTAssertFalse(remainingIDs.contains(200))
    }

    func testRemoveWindowCleansRegistry() {
        let (engine, _, enumerator, _) = LayoutEngine.makeForTesting()

        enumerator.windows = [makeWindowInfo(id: 100)]
        engine.addWindow(100)
        XCTAssertNotNil(engine.windowRegistry[100])

        engine.removeWindow(100)

        XCTAssertNil(engine.windowRegistry[100], "Window registry should no longer contain the removed ID")
    }

    func testRemoveWindowFromMultiWindowColumn() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Manually build a column with two windows [A, B]
        let column = Column(windowIDs: [100, 200], width: .proportion(0.5))
        engine.monitors[0].activeWorkspace.columns = [column]
        engine.windowRegistry[100] = makeWindowInfo(id: 100)
        engine.windowRegistry[200] = makeWindowInfo(id: 200)

        engine.removeWindow(100)

        let columns = engine.monitors[0].activeWorkspace.columns
        XCTAssertEqual(columns.count, 1, "Column should still exist because it has another window")
        XCTAssertEqual(columns[0].windowIDs, [200], "Only window 200 should remain in the column")
    }

    func testRemoveLastWindowInColumn() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Column with a single window
        let column = Column(windowIDs: [100], width: .proportion(0.5))
        engine.monitors[0].activeWorkspace.columns = [column]
        engine.windowRegistry[100] = makeWindowInfo(id: 100)

        engine.removeWindow(100)

        XCTAssertTrue(
            engine.monitors[0].activeWorkspace.columns.isEmpty,
            "Removing the last window in a column should remove the column entirely"
        )
    }

    func testRemoveWindowDoesNotCrashOnUnknown() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Engine has no windows at all. This should be a no-op, not a crash.
        engine.removeWindow(999)

        XCTAssertTrue(engine.monitors[0].activeWorkspace.columns.isEmpty)
    }

    // MARK: - Sync Focus

    func testSyncFocusFindsWindow() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Build 3 columns with one window each: 100, 200, 300
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
            Column(windowIDs: [200], width: .proportion(0.5)),
            Column(windowIDs: [300], width: .proportion(0.5)),
        ]
        engine.windowRegistry[100] = makeWindowInfo(id: 100)
        engine.windowRegistry[200] = makeWindowInfo(id: 200)
        engine.windowRegistry[300] = makeWindowInfo(id: 300)

        engine.syncFocus(to: 200)

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.focusedColumnIndex, 1, "syncFocus should set focusedColumnIndex to the column containing window 200")
    }

    func testSyncFocusAcrossWorkspaces() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Workspace 0 (active) has window 100
        engine.monitors[0].workspaces[0].columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
        ]

        // Create workspace 1 with window 200
        var ws2 = Workspace(id: 2)
        ws2.columns = [
            Column(windowIDs: [200], width: .proportion(0.5)),
        ]
        engine.monitors[0].workspaces.append(ws2)

        // Currently on workspace 0
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)

        engine.syncFocus(to: 200)

        XCTAssertEqual(
            engine.monitors[0].activeWorkspaceIndex, 1,
            "syncFocus should switch to workspace 1 where window 200 lives"
        )
    }

    func testSyncFocusWithinColumn() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Single column with two windows stacked
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200], width: .proportion(0.5)),
        ]
        engine.windowRegistry[100] = makeWindowInfo(id: 100)
        engine.windowRegistry[200] = makeWindowInfo(id: 200)

        engine.syncFocus(to: 200)

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.focusedColumnIndex, 0)
        XCTAssertEqual(ws.focusedWindowIndex, 1, "syncFocus should set focusedWindowIndex to 1 for the second window in the column")
    }
}
