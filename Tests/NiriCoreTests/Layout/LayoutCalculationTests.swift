import XCTest
import CoreGraphics
@testable import NiriCore

final class LayoutCalculationTests: XCTestCase {

    // MARK: - Helpers

    private let standardFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeEngine(config: LayoutConfig = LayoutConfig()) -> LayoutEngine {
        let (engine, _, _, _) = LayoutEngine.makeForTesting(config: config)
        return engine
    }

    private func makeWorkspace(
        columns: [Column],
        scrollOffset: CGFloat = 0
    ) -> Workspace {
        Workspace(
            id: 1,
            columns: columns,
            scrollOffset: scrollOffset,
            focusedColumnIndex: 0,
            focusedWindowIndex: 0
        )
    }

    // MARK: - Tests

    func testEmptyWorkspace() {
        let engine = makeEngine()
        let ws = makeWorkspace(columns: [])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertTrue(result.isEmpty, "Empty workspace should produce no layout results")
    }

    func testSingleColumnSingleWindow() {
        let engine = makeEngine()
        // Default config: gaps=16, outerGaps all 0
        let col = Column(windowIDs: [101], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 1)
        let (windowID, frame) = result[0]
        XCTAssertEqual(windowID, 101)

        // usableWidth = 1920 - 0 - 0 = 1920
        // columnWidth = (1920 - 16) * 0.5 = 952
        let expectedWidth: CGFloat = (1920 - 16) * 0.5
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(frame.size.width, expectedWidth, accuracy: 0.01)
        // Single window: usableHeight = 1080, totalGaps = 16*(1-1) = 0, height = 1080
        XCTAssertEqual(frame.size.height, 1080, accuracy: 0.01)
    }

    func testTwoColumnsSingleWindow() {
        let engine = makeEngine()
        let col1 = Column(windowIDs: [101], width: .proportion(0.5))
        let col2 = Column(windowIDs: [102], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col1, col2])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 2)

        let colWidth: CGFloat = (1920 - 16) * 0.5  // 952

        // First column: x = 0 (outerGaps.left=0 - scrollOffset=0)
        let (id1, frame1) = result[0]
        XCTAssertEqual(id1, 101)
        XCTAssertEqual(frame1.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame1.size.width, colWidth, accuracy: 0.01)

        // Second column: x = 952 + 16 = 968
        let (id2, frame2) = result[1]
        XCTAssertEqual(id2, 102)
        XCTAssertEqual(frame2.origin.x, colWidth + 16, accuracy: 0.01)
        XCTAssertEqual(frame2.size.width, colWidth, accuracy: 0.01)
    }

    func testColumnWithTwoWindows() {
        let engine = makeEngine()
        let col = Column(windowIDs: [101, 102], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 2)

        // usableHeight = 1080, 2 windows, totalGaps = 16*(2-1) = 16
        // windowHeight = (1080 - 16) / 2 = 532
        let expectedHeight: CGFloat = (1080 - 16) / 2

        let (id1, frame1) = result[0]
        XCTAssertEqual(id1, 101)
        XCTAssertEqual(frame1.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(frame1.size.height, expectedHeight, accuracy: 0.01)

        let (id2, frame2) = result[1]
        XCTAssertEqual(id2, 102)
        // second window y = 532 + 16 = 548
        XCTAssertEqual(frame2.origin.y, expectedHeight + 16, accuracy: 0.01)
        XCTAssertEqual(frame2.size.height, expectedHeight, accuracy: 0.01)
    }

    func testScrollOffset() {
        let engine = makeEngine()
        let col = Column(windowIDs: [101], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col], scrollOffset: 100)

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 1)
        let (_, frame) = result[0]
        // x = frame.origin.x + (outerGaps.left - scrollOffset) = 0 + (0 - 100) = -100
        XCTAssertEqual(frame.origin.x, -100, accuracy: 0.01)
    }

    func testOuterGaps() {
        var config = LayoutConfig()
        config.outerGaps = LayoutConfig.EdgeInsets(top: 10, bottom: 10, left: 10, right: 10)
        let engine = makeEngine(config: config)

        let col = Column(windowIDs: [101], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 1)
        let (_, frame) = result[0]

        // x starts at outerGaps.left = 10, so frame.origin.x = 0 + 10 = 10
        XCTAssertEqual(frame.origin.x, 10, accuracy: 0.01)
        // y = frame.origin.y + outerGaps.top = 0 + 10 = 10
        XCTAssertEqual(frame.origin.y, 10, accuracy: 0.01)

        // usableWidth = 1920 - 10 - 10 = 1900
        // columnWidth = (1900 - 16) * 0.5 = 942
        let expectedWidth: CGFloat = (1900 - 16) * 0.5
        XCTAssertEqual(frame.size.width, expectedWidth, accuracy: 0.01)

        // usableHeight = 1080 - 10 - 10 = 1060, single window, no inter-window gaps
        XCTAssertEqual(frame.size.height, 1060, accuracy: 0.01)
    }

    func testFixedWidth() {
        let engine = makeEngine()
        let col = Column(windowIDs: [101], width: .fixed(500))
        let ws = makeWorkspace(columns: [col])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 1)
        let (_, frame) = result[0]
        XCTAssertEqual(frame.size.width, 500, accuracy: 0.01)
    }

    func testMixedWidths() {
        let engine = makeEngine()
        let col1 = Column(windowIDs: [101], width: .proportion(0.5))
        let col2 = Column(windowIDs: [102], width: .fixed(300))
        let ws = makeWorkspace(columns: [col1, col2])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 2)

        let (_, frame1) = result[0]
        let (_, frame2) = result[1]

        let proportionWidth: CGFloat = (1920 - 16) * 0.5  // 952
        XCTAssertEqual(frame1.size.width, proportionWidth, accuracy: 0.01)
        XCTAssertEqual(frame2.size.width, 300, accuracy: 0.01)

        // Second column x = proportionWidth + gaps
        XCTAssertEqual(frame2.origin.x, proportionWidth + 16, accuracy: 0.01)
    }

    func testThreeWindowsInColumn() {
        let engine = makeEngine()
        let col = Column(windowIDs: [101, 102, 103], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 3)

        // usableHeight = 1080, 3 windows, totalGaps = 16*2 = 32
        // windowHeight = (1080 - 32) / 3 = 349.333...
        let expectedHeight: CGFloat = (1080 - 32) / 3

        for (i, (_, frame)) in result.enumerated() {
            XCTAssertEqual(frame.size.height, expectedHeight, accuracy: 0.01,
                           "Window \(i) height mismatch")
        }

        // Verify y positions chain correctly
        let (_, f0) = result[0]
        let (_, f1) = result[1]
        let (_, f2) = result[2]

        XCTAssertEqual(f0.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(f1.origin.y, expectedHeight + 16, accuracy: 0.01)
        XCTAssertEqual(f2.origin.y, 2 * (expectedHeight + 16), accuracy: 0.01)
    }

    func testMultipleColumnsMultipleWindows() {
        let engine = makeEngine()
        let col1 = Column(windowIDs: [101], width: .proportion(0.5))
        let col2 = Column(windowIDs: [201, 202], width: .proportion(0.5))
        let ws = makeWorkspace(columns: [col1, col2])

        let result = engine.calculateLayout(for: ws, in: standardFrame)

        XCTAssertEqual(result.count, 3)

        let colWidth: CGFloat = (1920 - 16) * 0.5  // 952
        let col2X: CGFloat = colWidth + 16           // 968
        let windowHeight: CGFloat = (1080 - 16) / 2  // 532

        // Column 1: single window, full usable height
        let (id0, f0) = result[0]
        XCTAssertEqual(id0, 101)
        XCTAssertEqual(f0.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(f0.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(f0.size.width, colWidth, accuracy: 0.01)
        XCTAssertEqual(f0.size.height, 1080, accuracy: 0.01)

        // Column 2, window 1
        let (id1, f1) = result[1]
        XCTAssertEqual(id1, 201)
        XCTAssertEqual(f1.origin.x, col2X, accuracy: 0.01)
        XCTAssertEqual(f1.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(f1.size.width, colWidth, accuracy: 0.01)
        XCTAssertEqual(f1.size.height, windowHeight, accuracy: 0.01)

        // Column 2, window 2
        let (id2, f2) = result[2]
        XCTAssertEqual(id2, 202)
        XCTAssertEqual(f2.origin.x, col2X, accuracy: 0.01)
        XCTAssertEqual(f2.origin.y, windowHeight + 16, accuracy: 0.01)
        XCTAssertEqual(f2.size.width, colWidth, accuracy: 0.01)
        XCTAssertEqual(f2.size.height, windowHeight, accuracy: 0.01)
    }
}
