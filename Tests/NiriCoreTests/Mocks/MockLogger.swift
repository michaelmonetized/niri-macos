import Foundation
@testable import NiriCore

final class MockLogger: Logging {

    // MARK: - Call recording

    private(set) var messages: [(level: String, message: String)] = []

    // MARK: - Logging

    func info(_ message: String) {
        messages.append((level: "info", message: message))
    }

    func error(_ message: String) {
        messages.append((level: "error", message: message))
    }

    func debug(_ message: String) {
        messages.append((level: "debug", message: message))
    }

    // MARK: - Helpers

    func reset() {
        messages.removeAll()
    }

    var infoMessages: [String] {
        messages.filter { $0.level == "info" }.map(\.message)
    }

    var errorMessages: [String] {
        messages.filter { $0.level == "error" }.map(\.message)
    }

    var debugMessages: [String] {
        messages.filter { $0.level == "debug" }.map(\.message)
    }
}
