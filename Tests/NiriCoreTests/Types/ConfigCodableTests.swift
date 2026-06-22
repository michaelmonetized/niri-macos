import XCTest
@testable import NiriCore

final class ConfigCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - NiriConfig

    func testNiriConfigRoundtrip() throws {
        let original = NiriConfig()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(NiriConfig.self, from: data)

        XCTAssertEqual(decoded.layout.gaps, original.layout.gaps)
        XCTAssertEqual(decoded.layout.centerFocusedColumn, original.layout.centerFocusedColumn)
        XCTAssertEqual(decoded.layout.defaultWidth, original.layout.defaultWidth)
        XCTAssertEqual(decoded.animation.enabled, original.animation.enabled)
        XCTAssertEqual(decoded.input.scrollThreshold, original.input.scrollThreshold)
        XCTAssertTrue(decoded.windowRules.isEmpty)
    }

    // MARK: - LayoutConfig.CenterMode

    func testLayoutConfigCenterMode() throws {
        let modes: [LayoutConfig.CenterMode] = [.never, .always, .onOverflow]
        for mode in modes {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(LayoutConfig.CenterMode.self, from: data)
            XCTAssertEqual(decoded, mode, "CenterMode \(mode) failed round-trip")
        }
    }

    // MARK: - SpringConfig

    func testSpringConfigRoundtrip() throws {
        let original = SpringConfig.snappy
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpringConfig.self, from: data)

        XCTAssertEqual(decoded.damping, original.damping, accuracy: 0.0001)
        XCTAssertEqual(decoded.stiffness, original.stiffness, accuracy: 0.0001)
        XCTAssertEqual(decoded.mass, original.mass, accuracy: 0.0001)
        XCTAssertEqual(decoded.epsilon, original.epsilon, accuracy: 0.0001)
    }

    // MARK: - WindowRule

    func testWindowRuleRoundtrip() throws {
        let original = WindowRule(
            matchers: [.appID("com.apple.Safari")],
            actions: [.float]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WindowRule.self, from: data)

        XCTAssertEqual(decoded.matchers.count, 1)
        XCTAssertEqual(decoded.actions.count, 1)

        // Verify matcher content via re-encode comparison
        let originalMatcherData = try encoder.encode(original.matchers)
        let decodedMatcherData = try encoder.encode(decoded.matchers)
        XCTAssertEqual(originalMatcherData, decodedMatcherData)

        let originalActionData = try encoder.encode(original.actions)
        let decodedActionData = try encoder.encode(decoded.actions)
        XCTAssertEqual(originalActionData, decodedActionData)
    }

    func testWindowRuleFixedWidthAction() throws {
        let original = WindowRule(
            matchers: [.appID("com.example.app")],
            actions: [.fixedWidth(800)]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WindowRule.self, from: data)

        // Round-trip the action and verify JSON equality
        let originalActionData = try encoder.encode(original.actions)
        let decodedActionData = try encoder.encode(decoded.actions)
        XCTAssertEqual(originalActionData, decodedActionData)
    }

    // MARK: - EdgeInsets

    func testEdgeInsetsRoundtrip() throws {
        let original = LayoutConfig.EdgeInsets(top: 10, bottom: 20, left: 30, right: 40)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LayoutConfig.EdgeInsets.self, from: data)

        XCTAssertEqual(decoded.top, 10, accuracy: 0.001)
        XCTAssertEqual(decoded.bottom, 20, accuracy: 0.001)
        XCTAssertEqual(decoded.left, 30, accuracy: 0.001)
        XCTAssertEqual(decoded.right, 40, accuracy: 0.001)
    }
}
