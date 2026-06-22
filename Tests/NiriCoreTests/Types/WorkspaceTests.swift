import XCTest
@testable import NiriCore

final class WorkspaceTests: XCTestCase {

    // MARK: - Empty workspace

    func testEmptyWorkspaceFocusedColumn() {
        let ws = Workspace(id: 1)
        XCTAssertNil(ws.focusedColumn)
    }

    func testEmptyWorkspaceFocusedWindowID() {
        let ws = Workspace(id: 1)
        XCTAssertNil(ws.focusedWindowID)
    }

    // MARK: - Valid focused column / window

    func testFocusedColumn() {
        let col0 = Column(windowIDs: [100], width: .proportion(0.5))
        let col1 = Column(windowIDs: [200, 300], width: .proportion(0.5))
        let ws = Workspace(
            id: 1,
            columns: [col0, col1],
            scrollOffset: 0,
            focusedColumnIndex: 1,
            focusedWindowIndex: 0
        )
        let focused = ws.focusedColumn
        XCTAssertNotNil(focused)
        XCTAssertEqual(focused?.windowIDs, [200, 300])
    }

    func testFocusedWindowID() {
        let col = Column(windowIDs: [100, 200], width: .proportion(0.5))
        let ws = Workspace(
            id: 1,
            columns: [col],
            scrollOffset: 0,
            focusedColumnIndex: 0,
            focusedWindowIndex: 1
        )
        XCTAssertEqual(ws.focusedWindowID, 200)
    }

    // MARK: - Out-of-bounds indices

    func testOutOfBoundsColumnIndex() {
        let col = Column(windowIDs: [100], width: .proportion(0.5))
        let ws = Workspace(
            id: 1,
            columns: [col, col],
            scrollOffset: 0,
            focusedColumnIndex: 5,
            focusedWindowIndex: 0
        )
        XCTAssertNil(ws.focusedColumn)
        XCTAssertNil(ws.focusedWindowID)
    }

    func testOutOfBoundsWindowIndex() {
        let col = Column(windowIDs: [100], width: .proportion(0.5))
        let ws = Workspace(
            id: 1,
            columns: [col],
            scrollOffset: 0,
            focusedColumnIndex: 0,
            focusedWindowIndex: 5
        )
        XCTAssertNotNil(ws.focusedColumn)
        XCTAssertNil(ws.focusedWindowID)
    }

    func testNegativeColumnIndex() {
        let col = Column(windowIDs: [100], width: .proportion(0.5))
        let ws = Workspace(
            id: 1,
            columns: [col],
            scrollOffset: 0,
            focusedColumnIndex: -1,
            focusedWindowIndex: 0
        )
        XCTAssertNil(ws.focusedColumn)
        XCTAssertNil(ws.focusedWindowID)
    }

    // MARK: - Default init

    func testDefaultInit() {
        let ws = Workspace(id: 1)
        XCTAssertEqual(ws.id, 1)
        XCTAssertTrue(ws.columns.isEmpty)
        XCTAssertEqual(ws.scrollOffset, 0)
        XCTAssertEqual(ws.focusedColumnIndex, 0)
        XCTAssertEqual(ws.focusedWindowIndex, 0)
    }
}
