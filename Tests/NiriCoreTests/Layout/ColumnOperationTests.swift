import XCTest
import CoreGraphics
@testable import NiriCore

final class ColumnOperationTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine() -> LayoutEngine {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()
        return engine
    }

    // MARK: - consumeWindowIntoColumn

    func testConsumeFromNextColumn() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
            Column(windowIDs: [200], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.consumeWindowIntoColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 1, "Empty column should be removed after consume")
        XCTAssertEqual(ws.columns[0].windowIDs, [100, 200], "Window from next column should be appended to current")
    }

    func testConsumeFromMultiWindowColumn() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
            Column(windowIDs: [200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.consumeWindowIntoColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 2, "Non-empty next column should remain")
        XCTAssertEqual(ws.columns[0].windowIDs, [100, 200], "First window from next column consumed")
        XCTAssertEqual(ws.columns[1].windowIDs, [300], "Remaining window stays in next column")
    }

    func testConsumeAtLastColumn() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
            Column(windowIDs: [200], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 1
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.consumeWindowIntoColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 2, "No change when focused on last column")
        XCTAssertEqual(ws.columns[0].windowIDs, [100])
        XCTAssertEqual(ws.columns[1].windowIDs, [200])
    }

    func testConsumeEmptyWorkspace() {
        let engine = makeEngine()
        // Workspace starts with no columns
        XCTAssertTrue(engine.monitors[0].activeWorkspace.columns.isEmpty)

        // Should not crash
        engine.consumeWindowIntoColumn()

        XCTAssertTrue(engine.monitors[0].activeWorkspace.columns.isEmpty)
    }

    // MARK: - expelWindowFromColumn

    func testExpelFromMultiWindowColumn() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.expelWindowFromColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 2, "Expel should create a new column")
        XCTAssertEqual(ws.columns[0].windowIDs, [200], "Remaining window stays in original column")
        XCTAssertEqual(ws.columns[1].windowIDs, [100], "Expelled window goes to new column")
        XCTAssertEqual(ws.focusedColumnIndex, 1, "Focus should move to the new column")
        XCTAssertEqual(ws.focusedWindowIndex, 0)
    }

    func testExpelSingleWindowColumn() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.expelWindowFromColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 1, "No change when column has only one window")
        XCTAssertEqual(ws.columns[0].windowIDs, [100])
    }

    func testExpelMiddleWindow() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100, 200, 300], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 1

        engine.expelWindowFromColumn()

        let ws = engine.monitors[0].activeWorkspace
        XCTAssertEqual(ws.columns.count, 2, "Expel should create a new column")
        XCTAssertEqual(ws.columns[0].windowIDs, [100, 300], "Middle window removed from original column")
        XCTAssertEqual(ws.columns[1].windowIDs, [200], "Expelled window in new column")
        XCTAssertEqual(ws.focusedColumnIndex, 1, "Focus moves to new column")
        XCTAssertEqual(ws.focusedWindowIndex, 0)
    }

    // MARK: - Round-trip

    func testConsumeAndExpelRoundtrip() {
        let engine = makeEngine()
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5)),
            Column(windowIDs: [200], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        // Consume: [100] [200] -> [100, 200]
        engine.consumeWindowIntoColumn()

        let wsAfterConsume = engine.monitors[0].activeWorkspace
        XCTAssertEqual(wsAfterConsume.columns.count, 1)
        XCTAssertEqual(wsAfterConsume.columns[0].windowIDs, [100, 200])

        // Focus the second window (the one we consumed) and expel it
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 1

        // Expel: [100, 200] -> [100] [200]
        engine.expelWindowFromColumn()

        let wsAfterExpel = engine.monitors[0].activeWorkspace
        XCTAssertEqual(wsAfterExpel.columns.count, 2, "Round-trip should return to 2 columns")
        XCTAssertEqual(wsAfterExpel.columns[0].windowIDs, [100])
        XCTAssertEqual(wsAfterExpel.columns[1].windowIDs, [200])
    }
}
