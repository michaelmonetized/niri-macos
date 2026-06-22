import XCTest
import CoreGraphics
@testable import NiriCore

final class FocusOperationTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine() -> (engine: LayoutEngine, controller: MockWindowController, enumerator: MockWindowEnumerator, logger: MockLogger) {
        LayoutEngine.makeForTesting()
    }

    /// Add three windows (100, 200, 300) each in its own column, then set focus to the given column/window index.
    private func engineWithThreeColumns(focusedColumn: Int = 1, focusedWindow: Int = 0) -> (LayoutEngine, MockWindowController) {
        let (engine, controller, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
            engine.addWindowToWorkspace(id, monitor: 0)
        }

        // After adding 100, 200, 300 in sequence the workspace has 3 columns.
        // addWindowToWorkspace always focuses the newly inserted column, so focus
        // ends up on the last one added. Override to the requested position.
        engine.monitors[0].activeWorkspace.focusedColumnIndex = focusedColumn
        engine.monitors[0].activeWorkspace.focusedWindowIndex = focusedWindow

        // Clear any focus calls that happened during setup
        controller.reset()

        return (engine, controller)
    }

    // MARK: - focusColumnLeft

    func testFocusColumnLeftFromMiddle() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 1)

        engine.focusColumnLeft()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    func testFocusColumnLeftAtBoundary() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 0)

        engine.focusColumnLeft()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0,
                       "focusColumnLeft should be a no-op when already at the leftmost column")
    }

    // MARK: - focusColumnRight

    func testFocusColumnRightFromMiddle() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 1)

        engine.focusColumnRight()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 2)
    }

    func testFocusColumnRightAtBoundary() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 2)

        engine.focusColumnRight()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 2,
                       "focusColumnRight should be a no-op when already at the rightmost column")
    }

    // MARK: - focusColumnFirst / focusColumnLast

    func testFocusColumnFirst() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 2)

        engine.focusColumnFirst()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    func testFocusColumnLast() {
        let (engine, _) = engineWithThreeColumns(focusedColumn: 0)

        engine.focusColumnLast()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 2)
    }

    func testFocusColumnFirstEmpty() {
        let (engine, _, _, _) = makeEngine()
        // Workspace is empty -- should not crash
        engine.focusColumnFirst()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    func testFocusColumnLastEmpty() {
        let (engine, _, _, _) = makeEngine()
        // Workspace is empty -- should not crash
        engine.focusColumnLast()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    // MARK: - focusWindowUp / focusWindowDown

    func testFocusWindowUp() {
        let (engine, controller, _, _) = makeEngine()

        // Create a single column with 3 windows
        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 2
        controller.reset()

        engine.focusWindowUp()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 1)
    }

    func testFocusWindowUpAtBoundary() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.focusWindowUp()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 0,
                       "focusWindowUp should be a no-op when already at the top window")
    }

    func testFocusWindowDown() {
        let (engine, controller, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0
        controller.reset()

        engine.focusWindowDown()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 1)
    }

    func testFocusWindowDownAtBoundary() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 2

        engine.focusWindowDown()

        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 2,
                       "focusWindowDown should be a no-op when already at the bottom window")
    }

    // MARK: - Focus calls window controller

    func testFocusCallsWindowController() {
        let (engine, controller) = engineWithThreeColumns(focusedColumn: 1)

        // Column 0 has window 100
        engine.focusColumnLeft()

        XCTAssertFalse(controller.focusCalls.isEmpty,
                       "focusColumnLeft should call windowController.focusWindow")
        XCTAssertEqual(controller.focusCalls.last, WindowID(100),
                       "focusColumnLeft should focus the window in the target column")
    }
}
