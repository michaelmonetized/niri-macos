import Foundation
import CoreGraphics
import AppKit

/// Controls window positions and sizes using Accessibility APIs
class WindowController {
    static let shared = WindowController()
    private let logger = Logger.shared
    private let enumerator = WindowEnumerator.shared
    
    // Cache of AXUIElement references for windows
    private var axWindowCache: [WindowID: AXUIElement] = [:]
    private var axAppCache: [pid_t: AXUIElement] = [:]
    
    private init() {}
    
    // MARK: - Window Manipulation
    
    /// Move a window to a new position
    func setWindowPosition(_ windowID: WindowID, position: CGPoint) -> Bool {
        guard let window = enumerator.getWindow(id: windowID),
              let axWindow = getAXWindow(for: window) else {
            logger.error("Cannot find window \(windowID) for position change")
            return false
        }
        
        var pos = position
        let positionValue = AXValueCreate(.cgPoint, &pos)!
        let result = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        
        if result != .success {
            logger.error("Failed to set position for window \(windowID): \(result.rawValue)")
            return false
        }
        
        return true
    }
    
    /// Resize a window
    func setWindowSize(_ windowID: WindowID, size: CGSize) -> Bool {
        guard let window = enumerator.getWindow(id: windowID),
              let axWindow = getAXWindow(for: window) else {
            logger.error("Cannot find window \(windowID) for size change")
            return false
        }
        
        var sz = size
        let sizeValue = AXValueCreate(.cgSize, &sz)!
        let result = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        
        if result != .success {
            logger.error("Failed to set size for window \(windowID): \(result.rawValue)")
            return false
        }
        
        return true
    }
    
    /// Move and resize a window in one operation
    func setWindowFrame(_ windowID: WindowID, frame: CGRect) -> Bool {
        // Set position first, then size (order matters for some apps)
        let posOk = setWindowPosition(windowID, position: frame.origin)
        let sizeOk = setWindowSize(windowID, size: frame.size)
        return posOk && sizeOk
    }
    
    /// Focus a window (bring to front and give keyboard focus)
    func focusWindow(_ windowID: WindowID) -> Bool {
        guard let window = enumerator.getWindow(id: windowID),
              let axWindow = getAXWindow(for: window) else {
            logger.error("Cannot find window \(windowID) for focus")
            return false
        }
        
        // Raise the window
        let raiseResult = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        if raiseResult != .success {
            logger.debug("Failed to set main window: \(raiseResult.rawValue)")
        }
        
        // Focus the window
        let focusResult = AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if focusResult != .success {
            logger.debug("Failed to focus window: \(focusResult.rawValue)")
        }
        
        // Activate the owning app
        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        return true
    }
    
    /// Minimize a window
    func minimizeWindow(_ windowID: WindowID) -> Bool {
        guard let window = enumerator.getWindow(id: windowID),
              let axWindow = getAXWindow(for: window) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return result == .success
    }
    
    /// Unminimize (restore) a window
    func unminimizeWindow(_ windowID: WindowID) -> Bool {
        guard let window = enumerator.getWindow(id: windowID),
              let axWindow = getAXWindow(for: window) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        return result == .success
    }
    
    // MARK: - AXUIElement Management
    
    /// Get or create AXUIElement for a window
    private func getAXWindow(for window: WindowInfo) -> AXUIElement? {
        // Check cache first
        if let cached = axWindowCache[window.id] {
            return cached
        }
        
        // Get or create app reference
        let axApp: AXUIElement
        if let cached = axAppCache[window.ownerPID] {
            axApp = cached
        } else {
            axApp = AXUIElementCreateApplication(window.ownerPID)
            axAppCache[window.ownerPID] = axApp
        }
        
        // Get all windows for this app
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            logger.debug("Failed to get windows for PID \(window.ownerPID)")
            return nil
        }
        
        // Find window by matching frame
        for axWindow in windows {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            var position = CGPoint.zero
            var size = CGSize.zero
            
            if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
               let posValue = positionRef {
                AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
            }
            
            if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            
            // Match by approximate position (allow small differences)
            if abs(position.x - window.frame.origin.x) < 5 &&
               abs(position.y - window.frame.origin.y) < 5 &&
               abs(size.width - window.frame.width) < 5 &&
               abs(size.height - window.frame.height) < 5 {
                axWindowCache[window.id] = axWindow
                return axWindow
            }
        }
        
        // Fallback: return first window if only one exists
        if windows.count == 1 {
            axWindowCache[window.id] = windows[0]
            return windows[0]
        }
        
        logger.debug("Could not match AXWindow for \(window.id) (\(window.title))")
        return nil
    }
    
    /// Clear cached AX references (call when apps quit)
    func clearCache(for pid: pid_t? = nil) {
        if let pid = pid {
            axAppCache.removeValue(forKey: pid)
            // Remove windows belonging to this app
            // We track this by checking if the window ID matches any from this app
            let appWindows = Set(WindowEnumerator.shared.getWindowsForApp(pid: pid).map { $0.id })
            axWindowCache = axWindowCache.filter { windowID, _ in
                !appWindows.contains(windowID)
            }
        } else {
            axAppCache.removeAll()
            axWindowCache.removeAll()
        }
    }
    
    // MARK: - Batch Operations
    
    /// Move multiple windows at once (more efficient)
    func batchSetFrames(_ frames: [(WindowID, CGRect)]) {
        for (windowID, frame) in frames {
            _ = setWindowFrame(windowID, frame: frame)
        }
    }
}
