import XCTest
import CoreGraphics
@testable import NiriCore

final class IPCCommandTests: XCTestCase {

    // MARK: - IPCCommand raw values

    func testAllCommandRawValues() {
        XCTAssertEqual(IPCCommand.focusColumnLeft.rawValue, "focus-column-left")
        XCTAssertEqual(IPCCommand.moveColumnRight.rawValue, "move-column-right")
        XCTAssertEqual(IPCCommand.consumeWindow.rawValue, "consume-window-into-column")
        XCTAssertEqual(IPCCommand.setColumnWidth.rawValue, "set-column-width")
        XCTAssertEqual(IPCCommand.workspaceDown.rawValue, "workspace-down")
        XCTAssertEqual(IPCCommand.toggleFullscreen.rawValue, "toggle-fullscreen")
        XCTAssertEqual(IPCCommand.quit.rawValue, "quit")
    }

    func testUnknownCommandRawValue() {
        XCTAssertNil(IPCCommand(rawValue: "nonexistent"))
        XCTAssertNil(IPCCommand(rawValue: ""))
        XCTAssertNil(IPCCommand(rawValue: "focus_column_left"))  // underscore instead of hyphen
    }

    // MARK: - IPCRequest decoding

    func testIPCRequestDecodeSimple() throws {
        let json = """
        {"command":"focus-column-left"}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(request.command, "focus-column-left")
        XCTAssertNil(request.args)
    }

    func testIPCRequestDecodeWithArgs() throws {
        let json = """
        {"command":"set-column-width","args":{"width":"50%"}}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(request.command, "set-column-width")
        XCTAssertEqual(request.args?["width"], "50%")
    }

    func testIPCRequestNilArgs() throws {
        let json = """
        {"command":"status"}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(request.command, "status")
        XCTAssertNil(request.args, "args should be nil when absent from JSON")
    }

    // MARK: - IPCResponse encoding

    func testIPCResponseEncodeSuccess() throws {
        let response = IPCResponse(success: true, error: nil, data: nil)
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"success\":true") || json.contains("\"success\" : true"),
                       "Encoded JSON should contain success:true")
    }

    func testIPCResponseEncodeError() throws {
        let response = IPCResponse(success: false, error: "bad", data: nil)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.error, "bad")
        XCTAssertNil(decoded.data)
    }

    func testIPCResponseWithData() throws {
        let original = IPCResponse(
            success: true,
            error: nil,
            data: ["key1": "value1", "key2": "value2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decoded.data?["key1"], "value1")
        XCTAssertEqual(decoded.data?["key2"], "value2")
    }
}
