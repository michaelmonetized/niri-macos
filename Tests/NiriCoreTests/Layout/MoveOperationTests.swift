import XCTest
import CoreGraphics
@testable import NiriCore

final class MoveOperationTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine() -> (engine: LayoutEngine, controller: MockWindowController, enumerator: MockWindowEnumerator, logger: MockLogger) {
        LayoutEngine.makeForTesting()
    }

    /// Add three windows (100, 200, 300) each in its own column, then set focus to the given column.
    private func engineWithThreeColumns(focusedColumn: Int = 1) -> LayoutEngine {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
            engine.addWindowToWorkspace(id, monitor: 0)
        }

        engine.monitors[0].activeWorkspace.focusedColumnIndex = focusedColumn
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        return engine
    }

    /// Return the window IDs from each column in order, e.g. [[100], [200], [300]].
    private func columnWindowIDs(_ engine: LayoutEngine) -> [[WindowID]] {
        engine.monitors[0].activeWorkspace.columns.map { $0.windowIDs }
    }

    // MARK: - moveColumnLeft

    func testMoveColumnLeftFromMiddle() {
        let engine = engineWithThreeColumns(focusedColumn: 1)

        // Columns before: [A=100], [B=200], [C=300], focused=1 (B)
        engine.moveColumnLeft()

        // Expected: [B=200], [A=100], [C=300], focused=0
        let ids = columnWindowIDs(engine)
        XCTAssertEqual(ids, [[200], [100], [300]])
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    func testMoveColumnLeftAtBoundary() {
        let engine = engineWithThreeColumns(focusedColumn: 0)

        let idsBefore = columnWindowIDs(engine)
        engine.moveColumnLeft()
        let idsAfter = columnWindowIDs(engine)

        XCTAssertEqual(idsBefore, idsAfter,
                       "moveColumnLeft should be a no-op when already at the leftmost column")
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 0)
    }

    // MARK: - moveColumnRight

    func testMoveColumnRightFromMiddle() {
        let engine = engineWithThreeColumns(focusedColumn: 1)

        // Columns before: [A=100], [B=200], [C=300], focused=1 (B)
        engine.moveColumnRight()

        // Expected: [A=100], [C=300], [B=200], focused=2
        let ids = columnWindowIDs(engine)
        XCTAssertEqual(ids, [[100], [300], [200]])
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 2)
    }

    func testMoveColumnRightAtBoundary() {
        let engine = engineWithThreeColumns(focusedColumn: 2)

        let idsBefore = columnWindowIDs(engine)
        engine.moveColumnRight()
        let idsAfter = columnWindowIDs(engine)

        XCTAssertEqual(idsBefore, idsAfter,
                       "moveColumnRight should be a no-op when already at the rightmost column")
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedColumnIndex, 2)
    }

    // MARK: - moveWindowUp

    func testMoveWindowUpInColumn() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 1

        engine.moveWindowUp()

        let windowIDs = engine.monitors[0].activeWorkspace.columns[0].windowIDs
        XCTAssertEqual(windowIDs, [200, 100, 300])
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 0)
    }

    func testMoveWindowUpAtTop() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.moveWindowUp()

        let windowIDs = engine.monitors[0].activeWorkspace.columns[0].windowIDs
        XCTAssertEqual(windowIDs, [100, 200, 300],
                       "moveWindowUp should be a no-op when already at the top")
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 0)
    }

    // MARK: - moveWindowDown

    func testMoveWindowDownInColumn() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 1

        engine.moveWindowDown()

        let windowIDs = engine.monitors[0].activeWorkspace.columns[0].windowIDs
        XCTAssertEqual(windowIDs, [100, 300, 200])
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 2)
    }

    func testMoveWindowDownAtBottom() {
        let (engine, _, _, _) = makeEngine()

        for id: WindowID in [100, 200, 300] {
            engine.windowRegistry[id] = makeWindowInfo(id: id)
        }
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 2

        engine.moveWindowDown()

        let windowIDs = engine.monitors[0].activeWorkspace.columns[0].windowIDs
        XCTAssertEqual(windowIDs, [100, 200, 300],
                       "moveWindowDown should be a no-op when already at the bottom")
        XCTAssertEqual(engine.monitors[0].activeWorkspace.focusedWindowIndex, 2)
    }
}
