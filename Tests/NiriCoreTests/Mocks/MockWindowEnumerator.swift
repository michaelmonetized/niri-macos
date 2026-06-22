import Foundation
import CoreGraphics
@testable import NiriCore

final class MockWindowEnumerator: WindowEnumerating {

    // MARK: - Configurable state

    var windows: [WindowInfo] = []

    // MARK: - WindowEnumerating

    func getAllWindows() -> [WindowInfo] {
        return windows
    }

    func getWindow(id: WindowID) -> WindowInfo? {
        return windows.first { $0.id == id }
    }

    func getWindowsForApp(pid: pid_t) -> [WindowInfo] {
        return windows.filter { $0.ownerPID == pid }
    }

    func getFocusedWindow() -> WindowInfo? {
        return nil
    }
}
