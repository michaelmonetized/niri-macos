import Foundation
import CoreGraphics

// MARK: - Window Manipulation Protocol

public protocol WindowManipulating {
    @discardableResult func setWindowPosition(_ windowID: WindowID, position: CGPoint) -> Bool
    @discardableResult func setWindowSize(_ windowID: WindowID, size: CGSize) -> Bool
    @discardableResult func setWindowFrame(_ windowID: WindowID, frame: CGRect) -> Bool
    @discardableResult func focusWindow(_ windowID: WindowID) -> Bool
    @discardableResult func minimizeWindow(_ windowID: WindowID) -> Bool
    func batchSetFrames(_ frames: [(WindowID, CGRect)])
    func clearCache(for pid: pid_t?)
}

// MARK: - Window Enumeration Protocol

public protocol WindowEnumerating {
    func getAllWindows() -> [WindowInfo]
    func getWindow(id: WindowID) -> WindowInfo?
    func getWindowsForApp(pid: pid_t) -> [WindowInfo]
    func getFocusedWindow() -> WindowInfo?
}

// MARK: - Logging Protocol

public protocol Logging {
    func info(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}
