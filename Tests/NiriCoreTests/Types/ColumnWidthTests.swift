import XCTest
@testable import NiriCore

final class ColumnWidthTests: XCTestCase {

    // MARK: - resolve(in:gaps:)

    func testProportionResolve() {
        let width = ColumnWidth.proportion(0.5)
        let resolved = width.resolve(in: 1000, gaps: 0)
        XCTAssertEqual(resolved, 500, accuracy: 0.001)
    }

    func testProportionResolveWithGaps() {
        let width = ColumnWidth.proportion(0.5)
        let resolved = width.resolve(in: 1000, gaps: 100)
        XCTAssertEqual(resolved, 450, accuracy: 0.001)
    }

    func testFixedResolve() {
        let width = ColumnWidth.fixed(800)
        // Fixed width ignores available width and gaps
        XCTAssertEqual(width.resolve(in: 1920, gaps: 16), 800, accuracy: 0.001)
        XCTAssertEqual(width.resolve(in: 500, gaps: 0), 800, accuracy: 0.001)
        XCTAssertEqual(width.resolve(in: 3000, gaps: 200), 800, accuracy: 0.001)
    }

    func testFullWidthProportion() {
        let width = ColumnWidth.proportion(1.0)
        let resolved = width.resolve(in: 1920, gaps: 0)
        XCTAssertEqual(resolved, 1920, accuracy: 0.001)
    }

    // MARK: - Presets

    func testPresetsCount() {
        XCTAssertEqual(ColumnWidth.presets.count, 4)
    }

    func testPresetsOrder() {
        let presets = ColumnWidth.presets
        XCTAssertEqual(presets.first, .proportion(0.33))
        XCTAssertEqual(presets.last, .proportion(1.0))
    }

    // MARK: - Equatable

    func testEquality() {
        XCTAssertEqual(ColumnWidth.proportion(0.5), ColumnWidth.proportion(0.5))
        XCTAssertEqual(ColumnWidth.fixed(800), ColumnWidth.fixed(800))
    }

    func testInequality() {
        XCTAssertNotEqual(ColumnWidth.proportion(0.5), ColumnWidth.fixed(500))
        XCTAssertNotEqual(ColumnWidth.proportion(0.33), ColumnWidth.proportion(0.5))
        XCTAssertNotEqual(ColumnWidth.fixed(800), ColumnWidth.fixed(900))
    }

    // MARK: - Codable round-trips

    func testCodableRoundtripProportion() throws {
        let original = ColumnWidth.proportion(0.66)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColumnWidth.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundtripFixed() throws {
        let original = ColumnWidth.fixed(1200)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColumnWidth.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
