import XCTest
import CoreGraphics
@testable import NiriCore

final class WorkspaceOperationTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine() -> LayoutEngine {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()
        return engine
    }

    /// Add a window to the active workspace of monitor 0 via the engine's helper.
    private func addWindow(_ windowID: WindowID, to engine: LayoutEngine) {
        engine.addWindowToWorkspace(windowID, monitor: 0)
    }

    // MARK: - workspaceUp

    func testWorkspaceUp() {
        let engine = makeEngine()
        // Create a second workspace and switch to it
        engine.monitors[0].workspaces.append(Workspace(id: 2))
        engine.monitors[0].activeWorkspaceIndex = 1

        engine.workspaceUp()

        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)
    }

    func testWorkspaceUpAtFirst() {
        let engine = makeEngine()
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)

        engine.workspaceUp()

        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0,
                       "Should stay at 0 when already on first workspace")
    }

    // MARK: - workspaceDown

    func testWorkspaceDown() {
        let engine = makeEngine()
        // Create a second workspace so we can go down without creating
        engine.monitors[0].workspaces.append(Workspace(id: 2))
        engine.monitors[0].activeWorkspaceIndex = 0

        engine.workspaceDown()

        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 1)
    }

    func testWorkspaceDownCreatesWorkspace() {
        let engine = makeEngine()
        XCTAssertEqual(engine.monitors[0].workspaces.count, 1,
                       "Monitor starts with 1 workspace")

        engine.workspaceDown()

        XCTAssertEqual(engine.monitors[0].workspaces.count, 2,
                       "workspaceDown should create a new workspace when at the last one")
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 1)
    }

    // MARK: - createWorkspaceBelow

    func testCreateWorkspaceBelow() {
        let engine = makeEngine()
        XCTAssertEqual(engine.monitors[0].workspaces.count, 1)
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)

        engine.createWorkspaceBelow()

        XCTAssertEqual(engine.monitors[0].workspaces.count, 2,
                       "Should have created a new workspace")
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 1,
                       "Should switch to the newly created workspace below")
    }

    // MARK: - createWorkspaceAbove

    func testCreateWorkspaceAbove() {
        let engine = makeEngine()
        // Add a window to the first workspace so we can distinguish them
        addWindow(100, to: engine)
        XCTAssertEqual(engine.monitors[0].workspaces.count, 1)

        engine.createWorkspaceAbove()

        XCTAssertEqual(engine.monitors[0].workspaces.count, 2,
                       "Should have created a new workspace")
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0,
                       "Should stay on index 0 (which is now the new empty workspace)")
        XCTAssertTrue(engine.monitors[0].workspaces[0].columns.isEmpty,
                      "New workspace at index 0 should be empty")
        XCTAssertFalse(engine.monitors[0].workspaces[1].columns.isEmpty,
                       "Original workspace should have moved to index 1")
    }

    // MARK: - focusWorkspace

    func testFocusWorkspace() {
        let engine = makeEngine()
        XCTAssertEqual(engine.monitors[0].workspaces.count, 1)

        // focusWorkspace is 1-indexed
        engine.focusWorkspace(3)

        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 2,
                       "Should switch to workspace index 2 (1-indexed input 3)")
        XCTAssertGreaterThanOrEqual(engine.monitors[0].workspaces.count, 3,
                                    "Should create workspaces as needed")
    }

    // MARK: - moveWindowToWorkspace

    func testMoveWindowToWorkspace() {
        let engine = makeEngine()
        addWindow(100, to: engine)

        // Verify window is on workspace 1
        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns.count, 1)
        XCTAssertEqual(engine.monitors[0].activeWorkspace.columns[0].windowIDs, [100])

        // Move to workspace 2 (1-indexed)
        engine.moveWindowToWorkspace(2)

        // Original workspace should be empty (column removed because it became empty)
        XCTAssertTrue(engine.monitors[0].workspaces[0].columns.isEmpty,
                      "Source workspace should have no columns after moving only window")

        // Target workspace should have the window
        XCTAssertEqual(engine.monitors[0].workspaces[1].columns.count, 1)
        XCTAssertEqual(engine.monitors[0].workspaces[1].columns[0].windowIDs, [100])
    }

    func testMoveWindowCreatesWorkspace() {
        let engine = makeEngine()
        addWindow(100, to: engine)
        XCTAssertEqual(engine.monitors[0].workspaces.count, 1)

        // Move to workspace 5 (1-indexed) - should create workspaces up to 5
        engine.moveWindowToWorkspace(5)

        XCTAssertGreaterThanOrEqual(engine.monitors[0].workspaces.count, 5,
                                    "Should create workspaces as needed up to target")
        XCTAssertEqual(engine.monitors[0].workspaces[4].columns.count, 1,
                       "Window should be on workspace 5 (index 4)")
        XCTAssertEqual(engine.monitors[0].workspaces[4].columns[0].windowIDs, [100])
    }

    // MARK: - Multiple workspace navigation

    func testWorkspaceDownMultiple() {
        let engine = makeEngine()
        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 0)

        engine.workspaceDown()
        engine.workspaceDown()
        engine.workspaceDown()

        XCTAssertEqual(engine.monitors[0].activeWorkspaceIndex, 3,
                       "Going down 3 times from 0 should land on index 3")
        XCTAssertEqual(engine.monitors[0].workspaces.count, 4,
                       "Should have created 4 workspaces total")
    }
}
