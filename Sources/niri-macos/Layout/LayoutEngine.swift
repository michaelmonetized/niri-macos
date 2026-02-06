import Foundation
import CoreGraphics
import AppKit

/// The core layout engine implementing niri's scrolling workspace paradigm
class LayoutEngine {
    static let shared = LayoutEngine()
    
    private let logger = Logger.shared
    private let windowEnumerator = WindowEnumerator.shared
    private let windowController = WindowController.shared
    
    // State
    private var monitors: [Monitor] = []
    private var windowRegistry: [WindowID: WindowInfo] = [:]
    private var floatingWindows: Set<WindowID> = []
    
    // Config
    var config = LayoutConfig()
    
    private init() {}
    
    // MARK: - Initialization
    
    func start() {
        logger.info("Layout engine starting...")
        
        // Enumerate monitors
        refreshMonitors()
        
        // Discover existing windows
        discoverWindows()
        
        // Apply initial layout
        applyLayout()
        
        logger.info("Layout engine ready with \(monitors.count) monitor(s), \(windowRegistry.count) window(s)")
    }
    
    func stop() {
        logger.info("Layout engine stopping...")
        monitors.removeAll()
        windowRegistry.removeAll()
    }
    
    // MARK: - Monitor Management
    
    private func refreshMonitors() {
        monitors.removeAll()
        
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            let frame = screen.visibleFrame
            let monitor = Monitor(displayID: displayID, frame: frame)
            monitors.append(monitor)
            
            logger.info("Monitor: \(displayID) at \(frame)")
        }
    }
    
    // MARK: - Window Discovery
    
    private func discoverWindows() {
        let windows = windowEnumerator.getAllWindows()
        
        for window in windows {
            // Skip already tracked windows
            if windowRegistry[window.id] != nil { continue }
            
            // Add to registry
            windowRegistry[window.id] = window
            
            // Add to layout (on primary monitor for now)
            if let monitor = monitors.first {
                addWindowToWorkspace(window.id, monitor: monitors.firstIndex(where: { $0.id == monitor.id })!)
            }
        }
    }
    
    private func addWindowToWorkspace(_ windowID: WindowID, monitor monitorIndex: Int) {
        guard monitorIndex < monitors.count else { return }
        
        // Create a new column for this window
        let column = Column(windowIDs: [windowID], width: config.defaultWidth)
        monitors[monitorIndex].activeWorkspace.columns.append(column)
        
        // Focus the new window
        let ws = monitors[monitorIndex].activeWorkspace
        monitors[monitorIndex].activeWorkspace.focusedColumnIndex = ws.columns.count - 1
        monitors[monitorIndex].activeWorkspace.focusedWindowIndex = 0
        
        logger.info("Added window \(windowID) to monitor \(monitorIndex), column \(ws.columns.count - 1)")
    }
    
    // MARK: - Layout Calculation
    
    /// Calculate target frames for all windows in a workspace
    func calculateLayout(for workspace: Workspace, in frame: CGRect) -> [(WindowID, CGRect)] {
        var results: [(WindowID, CGRect)] = []
        var x = config.outerGaps.left - workspace.scrollOffset
        let usableHeight = frame.height - config.outerGaps.top - config.outerGaps.bottom
        let usableWidth = frame.width - config.outerGaps.left - config.outerGaps.right
        
        for (colIndex, column) in workspace.columns.enumerated() {
            let columnWidth = column.width.resolve(in: usableWidth, gaps: config.gaps)
            
            // Calculate height for each window in column (split evenly)
            let windowCount = CGFloat(column.windowIDs.count)
            let totalGaps = config.gaps * (windowCount - 1)
            let windowHeight = (usableHeight - totalGaps) / windowCount
            
            var y = frame.origin.y + config.outerGaps.top
            
            for windowID in column.windowIDs {
                let windowFrame = CGRect(
                    x: frame.origin.x + x,
                    y: y,
                    width: columnWidth,
                    height: windowHeight
                )
                results.append((windowID, windowFrame))
                y += windowHeight + config.gaps
            }
            
            x += columnWidth + config.gaps
        }
        
        return results
    }
    
    /// Apply calculated layout to windows
    func applyLayout() {
        for monitor in monitors {
            let layout = calculateLayout(for: monitor.activeWorkspace, in: monitor.frame)
            
            for (windowID, frame) in layout {
                // Only move windows that are on-screen (visible in viewport)
                let viewportLeft = monitor.frame.origin.x
                let viewportRight = monitor.frame.origin.x + monitor.frame.width
                
                if frame.maxX >= viewportLeft && frame.minX <= viewportRight {
                    // Window is at least partially visible
                    _ = windowController.setWindowFrame(windowID, frame: frame)
                }
            }
        }
    }
    
    // MARK: - Focus Operations
    
    func focusColumnLeft() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        if ws.focusedColumnIndex > 0 {
            ws.focusedColumnIndex -= 1
            ws.focusedWindowIndex = 0
            monitors[monitorIdx].activeWorkspace = ws
            
            // Scroll to show focused column
            scrollToFocus(monitorIndex: monitorIdx)
            
            // Focus the window
            if let windowID = ws.focusedWindowID {
                _ = windowController.focusWindow(windowID)
            }
        }
    }
    
    func focusColumnRight() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        if ws.focusedColumnIndex < ws.columns.count - 1 {
            ws.focusedColumnIndex += 1
            ws.focusedWindowIndex = 0
            monitors[monitorIdx].activeWorkspace = ws
            
            scrollToFocus(monitorIndex: monitorIdx)
            
            if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
                _ = windowController.focusWindow(windowID)
            }
        }
    }
    
    func focusWindowUp() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard let col = ws.focusedColumn, ws.focusedWindowIndex > 0 else { return }
        
        ws.focusedWindowIndex -= 1
        monitors[monitorIdx].activeWorkspace = ws
        
        if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
            _ = windowController.focusWindow(windowID)
        }
    }
    
    func focusWindowDown() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard let col = ws.focusedColumn, ws.focusedWindowIndex < col.windowIDs.count - 1 else { return }
        
        ws.focusedWindowIndex += 1
        monitors[monitorIdx].activeWorkspace = ws
        
        if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
            _ = windowController.focusWindow(windowID)
        }
    }
    
    // MARK: - Move Operations
    
    func moveColumnLeft() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex > 0 else { return }
        
        let idx = ws.focusedColumnIndex
        ws.columns.swapAt(idx, idx - 1)
        ws.focusedColumnIndex -= 1
        monitors[monitorIdx].activeWorkspace = ws
        
        scrollToFocus(monitorIndex: monitorIdx)
        applyLayout()
    }
    
    func moveColumnRight() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count - 1 else { return }
        
        let idx = ws.focusedColumnIndex
        ws.columns.swapAt(idx, idx + 1)
        ws.focusedColumnIndex += 1
        monitors[monitorIdx].activeWorkspace = ws
        
        scrollToFocus(monitorIndex: monitorIdx)
        applyLayout()
    }
    
    // MARK: - Column Operations
    
    func consumeWindowIntoColumn() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count - 1 else { return }
        
        // Take first window from next column and add to current
        let nextIdx = ws.focusedColumnIndex + 1
        guard !ws.columns[nextIdx].windowIDs.isEmpty else { return }
        
        let windowID = ws.columns[nextIdx].windowIDs.removeFirst()
        ws.columns[ws.focusedColumnIndex].windowIDs.append(windowID)
        
        // Remove empty column
        if ws.columns[nextIdx].windowIDs.isEmpty {
            ws.columns.remove(at: nextIdx)
        }
        
        monitors[monitorIdx].activeWorkspace = ws
        applyLayout()
    }
    
    func expelWindowFromColumn() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard let col = ws.focusedColumn, col.windowIDs.count > 1 else { return }
        
        // Take focused window and create new column
        let windowID = ws.columns[ws.focusedColumnIndex].windowIDs.remove(at: ws.focusedWindowIndex)
        
        let newColumn = Column(windowIDs: [windowID], width: config.defaultWidth)
        ws.columns.insert(newColumn, at: ws.focusedColumnIndex + 1)
        
        ws.focusedColumnIndex += 1
        ws.focusedWindowIndex = 0
        
        monitors[monitorIdx].activeWorkspace = ws
        applyLayout()
    }
    
    // MARK: - Size Operations
    
    func switchPresetColumnWidth() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count else { return }
        
        let current = ws.columns[ws.focusedColumnIndex].width
        let presets = config.presetWidths
        
        // Find current preset index and move to next
        if let idx = presets.firstIndex(of: current) {
            let nextIdx = (idx + 1) % presets.count
            ws.columns[ws.focusedColumnIndex].width = presets[nextIdx]
        } else {
            ws.columns[ws.focusedColumnIndex].width = presets[0]
        }
        
        monitors[monitorIdx].activeWorkspace = ws
        applyLayout()
    }
    
    func centerColumn() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        let monitor = monitors[monitorIdx]
        
        // Calculate position of focused column
        let layout = calculateLayout(for: ws, in: monitor.frame)
        guard let focusedWindowID = ws.focusedWindowID,
              let (_, focusedFrame) = layout.first(where: { $0.0 == focusedWindowID }) else { return }
        
        // Calculate scroll offset to center this column
        let columnCenter = focusedFrame.midX
        let viewportCenter = monitor.frame.midX
        let adjustment = columnCenter - viewportCenter
        
        ws.scrollOffset += adjustment
        monitors[monitorIdx].activeWorkspace = ws
        
        applyLayout()
    }
    
    // MARK: - Scroll Operations
    
    func scroll(by delta: CGFloat) {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        monitors[monitorIdx].activeWorkspace.scrollOffset += delta
        applyLayout()
    }
    
    private func scrollToFocus(monitorIndex: Int) {
        let ws = monitors[monitorIndex].activeWorkspace
        let monitor = monitors[monitorIndex]
        
        // Calculate current focus position
        let layout = calculateLayout(for: ws, in: monitor.frame)
        guard let focusedWindowID = ws.focusedWindowID,
              let (_, focusedFrame) = layout.first(where: { $0.0 == focusedWindowID }) else { return }
        
        // Check if focused window is fully visible
        let viewportLeft = monitor.frame.origin.x
        let viewportRight = monitor.frame.origin.x + monitor.frame.width
        
        var newOffset = ws.scrollOffset
        
        if focusedFrame.minX < viewportLeft {
            // Window is off-screen to the left
            newOffset -= (viewportLeft - focusedFrame.minX) + config.gaps
        } else if focusedFrame.maxX > viewportRight {
            // Window is off-screen to the right
            newOffset += (focusedFrame.maxX - viewportRight) + config.gaps
        }
        
        if newOffset != ws.scrollOffset {
            monitors[monitorIndex].activeWorkspace.scrollOffset = newOffset
            applyLayout()
        }
    }
    
    // MARK: - Helpers
    
    /// Get current active monitor and workspace indices
    private func getActiveContext() -> (Int, Int)? {
        // For now, just use the first monitor
        // TODO: Determine based on focused window or mouse position
        guard !monitors.isEmpty else { return nil }
        return (0, monitors[0].activeWorkspaceIndex)
    }
    
    /// Debug: print current state
    func debugPrint() {
        logger.info("=== Layout State ===")
        for (i, monitor) in monitors.enumerated() {
            logger.info("Monitor \(i): \(monitor.frame)")
            let ws = monitor.activeWorkspace
            logger.info("  Workspace \(ws.id): scroll=\(ws.scrollOffset), focus=(\(ws.focusedColumnIndex), \(ws.focusedWindowIndex))")
            for (j, col) in ws.columns.enumerated() {
                logger.info("    Column \(j): \(col.windowIDs.count) windows, width=\(col.width)")
            }
        }
    }
}
