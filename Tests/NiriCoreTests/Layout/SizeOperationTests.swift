import XCTest
import CoreGraphics
@testable import NiriCore

final class SizeOperationTests: XCTestCase {

    // MARK: - Helpers

    /// Create an engine with a single window so there is a focused column to operate on.
    private func makeEngineWithOneWindow(
        initialWidth: ColumnWidth = .proportion(0.5)
    ) -> LayoutEngine {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        // Add a single column with one window
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: initialWidth)
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        return engine
    }

    private func focusedWidth(_ engine: LayoutEngine) -> ColumnWidth {
        let ws = engine.monitors[0].activeWorkspace
        return ws.columns[ws.focusedColumnIndex].width
    }

    // MARK: - switchPresetColumnWidth

    func testSwitchPresetCycles() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(0.5))

        // 0.5 -> next preset -> 0.66
        engine.switchPresetColumnWidth()
        XCTAssertEqual(focusedWidth(engine), .proportion(0.66))

        // 0.66 -> 1.0
        engine.switchPresetColumnWidth()
        XCTAssertEqual(focusedWidth(engine), .proportion(1.0))

        // 1.0 -> wraps to 0.33
        engine.switchPresetColumnWidth()
        XCTAssertEqual(focusedWidth(engine), .proportion(0.33))
    }

    func testSwitchPresetFromUnknownWidth() {
        let engine = makeEngineWithOneWindow(initialWidth: .fixed(500))

        // Unknown width should jump to first preset
        engine.switchPresetColumnWidth()
        XCTAssertEqual(focusedWidth(engine), .proportion(0.33))
    }

    // MARK: - maximizeColumn

    func testMaximizeColumn() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(0.5))

        engine.maximizeColumn()

        XCTAssertEqual(focusedWidth(engine), .proportion(1.0))
    }

    // MARK: - toggleFullscreen

    func testToggleFullscreenMaximize() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(0.5))

        engine.toggleFullscreen()

        XCTAssertEqual(focusedWidth(engine), .proportion(1.0),
                       "Toggle from non-maximized should maximize")
    }

    func testToggleFullscreenRestore() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(1.0))

        engine.toggleFullscreen()

        // Should restore to config.defaultWidth which is .proportion(0.5)
        XCTAssertEqual(focusedWidth(engine), .proportion(0.5),
                       "Toggle from maximized should restore to default width")
    }

    // MARK: - setColumnWidth

    func testSetColumnWidthAbsolutePercent() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(0.33))

        engine.setColumnWidth("50%")

        XCTAssertEqual(focusedWidth(engine), .proportion(0.5))
    }

    func testSetColumnWidthRelativePercent() {
        // Use zero gaps so proportion resolves cleanly: currentWidth / usableWidth == proportion
        var config = LayoutConfig()
        config.gaps = 0
        let (engine, _, _, _) = LayoutEngine.makeForTesting(config: config)
        engine.monitors[0].activeWorkspace.columns = [
            Column(windowIDs: [100], width: .proportion(0.5))
        ]
        engine.monitors[0].activeWorkspace.focusedColumnIndex = 0
        engine.monitors[0].activeWorkspace.focusedWindowIndex = 0

        engine.setColumnWidth("+10%")

        XCTAssertEqual(focusedWidth(engine), .proportion(0.6))
    }

    func testSetColumnWidthAbsolutePixels() {
        let engine = makeEngineWithOneWindow(initialWidth: .proportion(0.5))

        engine.setColumnWidth("800")

        XCTAssertEqual(focusedWidth(engine), .fixed(800))
    }
}
