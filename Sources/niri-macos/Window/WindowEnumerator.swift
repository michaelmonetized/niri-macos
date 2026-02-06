import Foundation
import CoreGraphics
import AppKit

/// Enumerates and tracks windows using CGWindowList APIs
class WindowEnumerator {
    static let shared = WindowEnumerator()
    private let logger = Logger.shared
    
    private init() {}
    
    /// Get all windows currently on screen
    func getAllWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            logger.error("Failed to get window list")
            return []
        }
        
        return windowList.compactMap { parseWindowInfo($0) }
            .filter { $0.isStandardWindow }
    }
    
    /// Get windows for a specific app
    func getWindowsForApp(pid: pid_t) -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowList.compactMap { parseWindowInfo($0) }
            .filter { $0.ownerPID == pid && $0.isStandardWindow }
    }
    
    /// Get a specific window by ID
    func getWindow(id: WindowID) -> WindowInfo? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let dict = windowList.first else {
            return nil
        }
        return parseWindowInfo(dict)
    }
    
    /// Parse window dictionary from CGWindowList
    private func parseWindowInfo(_ dict: [String: Any]) -> WindowInfo? {
        guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
              let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
              let layer = dict[kCGWindowLayer as String] as? Int32 else {
            return nil
        }
        
        let appName = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
        let title = dict[kCGWindowName as String] as? String ?? ""
        let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
        
        let frame = CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
        
        // Get bundle ID from running application
        let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
        
        return WindowInfo(
            id: windowID,
            ownerPID: ownerPID,
            bundleID: bundleID,
            appName: appName,
            title: title,
            frame: frame,
            space: 0,  // TODO: Get from CGS private API
            isOnScreen: isOnScreen,
            isMinimized: false,  // TODO: Get from AX
            layer: layer
        )
    }
    
    /// Check if we have accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Get the frontmost (focused) application
    func getFrontmostApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    /// Get the focused window using Accessibility APIs
    func getFocusedWindow() -> WindowInfo? {
        guard let app = getFrontmostApp() else { return nil }
        
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success, let windowRef = focusedWindow else {
            return nil
        }
        
        // Get window position and size
        var position = CGPoint.zero
        var size = CGSize.zero
        
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success,
           let posValue = positionRef {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        }
        
        if AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        
        let frame = CGRect(origin: position, size: size)
        
        // Get title
        var titleRef: CFTypeRef?
        var title = ""
        if AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleStr = titleRef as? String {
            title = titleStr
        }
        
        // Find matching CGWindow to get ID
        let windows = getWindowsForApp(pid: app.processIdentifier)
        let matched = windows.first { window in
            // Match by approximate frame (AX and CG frames can differ slightly)
            abs(window.frame.origin.x - frame.origin.x) < 5 &&
            abs(window.frame.origin.y - frame.origin.y) < 5
        }
        
        if let matched = matched {
            return matched
        }
        
        // Fallback: create WindowInfo without CGWindowID
        return WindowInfo(
            id: 0,
            ownerPID: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "Unknown",
            title: title,
            frame: frame,
            space: 0,
            isOnScreen: true,
            isMinimized: false,
            layer: 0
        )
    }
}
