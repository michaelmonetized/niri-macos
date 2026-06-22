import XCTest
import CoreGraphics
@testable import NiriCore

final class ScrollTests: XCTestCase {

    // MARK: - Helpers

    private let standardFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Tests

    func testScrollModifiesOffset() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        engine.scroll(by: 100)

        let offset = engine.monitors[0].activeWorkspace.scrollOffset
        XCTAssertEqual(offset, 100, accuracy: 0.01, "scroll(by: 100) should set scrollOffset to 100")
    }

    func testScrollAccumulates() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        engine.scroll(by: 50)
        engine.scroll(by: 50)

        let offset = engine.monitors[0].activeWorkspace.scrollOffset
        XCTAssertEqual(offset, 100, accuracy: 0.01, "Two scroll(by: 50) calls should accumulate to 100")
    }

    func testScrollNegative() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        engine.scroll(by: -100)

        let offset = engine.monitors[0].activeWorkspace.scrollOffset
        XCTAssertEqual(offset, -100, accuracy: 0.01, "scroll(by: -100) should set scrollOffset to -100")
    }

    func testScrollAffectsLayout() {
        let (engine, _, _, _) = LayoutEngine.makeForTesting()

        let col = Column(windowIDs: [101], width: .proportion(0.5))
        let wsNoScroll = Workspace(
            id: 1,
            columns: [col],
            scrollOffset: 0,
            focusedColumnIndex: 0,
            focusedWindowIndex: 0
        )

        let resultNoScroll = engine.calculateLayout(for: wsNoScroll, in: standardFrame)
        XCTAssertEqual(resultNoScroll.count, 1)
        let baseX = resultNoScroll[0].1.origin.x

        // Now with scrollOffset = 100
        let wsWithScroll = Workspace(
            id: 1,
            columns: [col],
            scrollOffset: 100,
            focusedColumnIndex: 0,
            focusedWindowIndex: 0
        )

        let resultWithScroll = engine.calculateLayout(for: wsWithScroll, in: standardFrame)
        XCTAssertEqual(resultWithScroll.count, 1)
        let scrolledX = resultWithScroll[0].1.origin.x

        XCTAssertEqual(
            scrolledX, baseX - 100, accuracy: 0.01,
            "A scrollOffset of 100 should shift the window 100 points to the left"
        )
    }
}
