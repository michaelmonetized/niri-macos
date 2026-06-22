import Foundation
import CoreGraphics
import AppKit

/// Observes window events via Accessibility APIs for real-time updates
public class AXWindowObserver {
    public static let shared = AXWindowObserver()
    
    private let logger = Logger.shared
    private var observers: [pid_t: AXObserver] = [:]
    private var axAppRefs: [pid_t: AXUIElement] = [:]
    private var appObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    
    // Callbacks
    public var onWindowCreated: ((WindowID, pid_t) -> Void)?
    public var onWindowDestroyed: ((WindowID, pid_t) -> Void)?
    public var onWindowMoved: ((WindowID, CGRect) -> Void)?
    public var onWindowResized: ((WindowID, CGRect) -> Void)?
    public var onWindowFocused: ((WindowID) -> Void)?
    public var onWindowMinimized: ((WindowID, Bool) -> Void)?
    public var onWindowTitleChanged: ((WindowID, String) -> Void)?
    
    private init() {}
    
    // MARK: - Lifecycle
    
    public func start() {
        logger.info("AX Observer starting...")
        
        // Observe app launches
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.registerApp(app)
            }
        }
        
        // Observe app terminations
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.unregisterApp(app.processIdentifier)
            }
        }
        
        // Register all currently running apps
        for app in NSWorkspace.shared.runningApplications {
            registerApp(app)
        }
        
        logger.info("AX Observer started with \(observers.count) apps")
    }
    
    public func stop() {
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        
        // Remove all observers
        for (pid, _) in observers {
            unregisterApp(pid)
        }
        
        observers.removeAll()
        axAppRefs.removeAll()
        
        logger.info("AX Observer stopped")
    }
    
    // MARK: - App Registration
    
    private func registerApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        
        // Skip system apps and ourselves
        guard app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        
        // Skip if already registered
        guard observers[pid] == nil else { return }
        
        // Create AX observer
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)
        
        guard result == .success, let observer = observer else {
            logger.debug("Failed to create AX observer for \(app.localizedName ?? "Unknown") (pid: \(pid)): \(result.rawValue)")
            return
        }
        
        // Create AXUIElement for the app
        let axApp = AXUIElementCreateApplication(pid)
        axAppRefs[pid] = axApp
        
        // Subscribe to notifications
        let notifications: [String] = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXTitleChangedNotification,
            kAXMainWindowChangedNotification,
        ]
        
        for notification in notifications {
            let addResult = AXObserverAddNotification(observer, axApp, notification as CFString, UnsafeMutableRawPointer(bitPattern: Int(pid)))
            if addResult != .success && addResult != .notificationAlreadyRegistered {
                logger.debug("Failed to add \(notification) for pid \(pid): \(addResult.rawValue)")
            }
        }
        
        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        
        observers[pid] = observer
        logger.debug("Registered AX observer for \(app.localizedName ?? "Unknown") (pid: \(pid))")
        
        // Get initial windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scanInitialWindows(pid: pid)
        }
    }
    
    private func unregisterApp(_ pid: pid_t) {
        guard let observer = observers[pid] else { return }
        
        // Remove from run loop
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        
        observers.removeValue(forKey: pid)
        axAppRefs.removeValue(forKey: pid)
        
        logger.debug("Unregistered AX observer for pid \(pid)")
    }
    
    // MARK: - Window Scanning
    
    private func scanInitialWindows(pid: pid_t) {
        guard let axApp = axAppRefs[pid] else { return }
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return
        }
        
        for axWindow in windows {
            if let windowID = getWindowID(for: axWindow, pid: pid) {
                onWindowCreated?(windowID, pid)
            }
        }
    }
    
    // MARK: - Window ID Resolution
    
    /// Get CGWindowID for an AXUIElement window
    public func getWindowID(for axWindow: AXUIElement, pid: pid_t) -> WindowID? {
        // Get window position and size from AX
        var position = CGPoint.zero
        var size = CGSize.zero
        
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
           let posValue = positionRef {
            // CFTypeRef -> AXValue cast always succeeds for position attributes
            let posAXValue = unsafeBitCast(posValue, to: AXValue.self)
            AXValueGetValue(posAXValue, .cgPoint, &position)
        }
        
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            // CFTypeRef -> AXValue cast always succeeds for size attributes
            let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        }
        
        // Find matching CGWindow
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for dict in windowList {
            guard let windowPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid,
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = dict[kCGWindowLayer as String] as? Int32,
                  layer == 0 else {
                continue
            }
            
            let wx = bounds["X"] ?? 0
            let wy = bounds["Y"] ?? 0
            let ww = bounds["Width"] ?? 0
            let wh = bounds["Height"] ?? 0
            
            // Match by approximate frame (wider tolerance for AX-to-CG matching)
            let cgFrame = CGRect(x: wx, y: wy, width: ww, height: wh)
            let axFrame = CGRect(origin: position, size: size)
            if WindowEnumerator.framesMatch(cgFrame, axFrame) {
                return windowID
            }
        }
        
        return nil
    }
    
    /// Get current frame from AXUIElement
    public func getWindowFrame(for axWindow: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
           let posValue = positionRef {
            // CFTypeRef -> AXValue cast always succeeds for position attributes
            let posAXValue = unsafeBitCast(posValue, to: AXValue.self)
            AXValueGetValue(posAXValue, .cgPoint, &position)
        } else {
            return nil
        }
        
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            // CFTypeRef -> AXValue cast always succeeds for size attributes
            let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        } else {
            return nil
        }
        
        return CGRect(origin: position, size: size)
    }
    
    /// Get window title from AXUIElement
    public func getWindowTitle(for axWindow: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String {
            return title
        }
        return nil
    }
    
    // MARK: - AX Callback Handler
    
    public func handleNotification(_ notification: String, element: AXUIElement, pid: pid_t) {
        switch notification {
        case kAXWindowCreatedNotification:
            if let windowID = getWindowID(for: element, pid: pid) {
                logger.debug("Window created: \(windowID) (pid: \(pid))")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowCreated?(windowID, pid)
                }
            }
            
        case kAXUIElementDestroyedNotification:
            // Element is already destroyed, can't get info
            // Layout engine will handle orphaned windows during refresh
            logger.debug("Window destroyed (pid: \(pid))")
            // We'll trigger a refresh
            DispatchQueue.main.async { [weak self] in
                self?.onWindowDestroyed?(0, pid)
            }
            
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if let windowID = getWindowID(for: element, pid: pid) {
                logger.debug("Window focused: \(windowID)")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowFocused?(windowID)
                }
            }
            
        case kAXWindowMovedNotification:
            if let windowID = getWindowID(for: element, pid: pid),
               let frame = getWindowFrame(for: element) {
                logger.debug("Window moved: \(windowID) to \(frame)")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowMoved?(windowID, frame)
                }
            }
            
        case kAXWindowResizedNotification:
            if let windowID = getWindowID(for: element, pid: pid),
               let frame = getWindowFrame(for: element) {
                logger.debug("Window resized: \(windowID) to \(frame)")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowResized?(windowID, frame)
                }
            }
            
        case kAXWindowMiniaturizedNotification:
            if let windowID = getWindowID(for: element, pid: pid) {
                logger.debug("Window minimized: \(windowID)")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowMinimized?(windowID, true)
                }
            }
            
        case kAXWindowDeminiaturizedNotification:
            if let windowID = getWindowID(for: element, pid: pid) {
                logger.debug("Window unminimized: \(windowID)")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowMinimized?(windowID, false)
                }
            }
            
        case kAXTitleChangedNotification:
            if let windowID = getWindowID(for: element, pid: pid),
               let title = getWindowTitle(for: element) {
                logger.debug("Window title changed: \(windowID) to '\(title)'")
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowTitleChanged?(windowID, title)
                }
            }
            
        default:
            break
        }
    }
}

// MARK: - AX Callback (C function)

private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else { return }
    let pid = pid_t(Int(bitPattern: userData))
    let notificationStr = notification as String
    
    AXWindowObserver.shared.handleNotification(notificationStr, element: element, pid: pid)
}
