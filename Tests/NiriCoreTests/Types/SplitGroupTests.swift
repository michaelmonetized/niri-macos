import XCTest
@testable import NiriCore

final class SplitGroupTests: XCTestCase {

    // MARK: - requiredWindowCount

    func testHorizontalRequiredCount() {
        let group = SplitGroup(layout: .horizontal, windowIDs: [], width: .proportion(0.5))
        XCTAssertEqual(group.requiredWindowCount, 2)
    }

    func testVerticalRequiredCount() {
        let group = SplitGroup(layout: .vertical, windowIDs: [], width: .proportion(0.5))
        XCTAssertEqual(group.requiredWindowCount, 2)
    }

    func testQuadRequiredCount() {
        let group = SplitGroup(layout: .quad, windowIDs: [], width: .proportion(0.5))
        XCTAssertEqual(group.requiredWindowCount, 4)
    }

    // MARK: - isFull

    func testIsFullHorizontal() {
        let full = SplitGroup(layout: .horizontal, windowIDs: [1, 2], width: .proportion(0.5))
        XCTAssertTrue(full.isFull)

        let notFull = SplitGroup(layout: .horizontal, windowIDs: [1], width: .proportion(0.5))
        XCTAssertFalse(notFull.isFull)
    }

    func testIsFullQuad() {
        let full = SplitGroup(layout: .quad, windowIDs: [1, 2, 3, 4], width: .proportion(0.5))
        XCTAssertTrue(full.isFull)

        let notFull = SplitGroup(layout: .quad, windowIDs: [1, 2, 3], width: .proportion(0.5))
        XCTAssertFalse(notFull.isFull)
    }

    // MARK: - isEmpty

    func testIsEmpty() {
        let empty = SplitGroup(layout: .horizontal, windowIDs: [], width: .proportion(0.5))
        XCTAssertTrue(empty.isEmpty)

        let notEmpty = SplitGroup(layout: .horizontal, windowIDs: [1], width: .proportion(0.5))
        XCTAssertFalse(notEmpty.isEmpty)
    }
}
