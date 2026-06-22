import Foundation
import CoreGraphics
import AppKit
import QuartzCore

/// The core layout engine implementing niri's scrolling workspace paradigm
public class LayoutEngine {
    public static let shared = LayoutEngine()

    let logger: Logging
    let windowEnumerator: WindowEnumerating
    let windowController: WindowManipulating
    private let animationController: AnimationController

    // State (internal for test inspection)
    var monitors: [Monitor] = []
    var windowRegistry: [WindowID: WindowInfo] = [:]
    var floatingWindows: Set<WindowID> = []

    // Scroll animation state
    private var targetScrollOffset: CGFloat = 0
    private var isAnimatingScroll = false
    private var scrollAnimationTimer: Timer?

    // Config
    public var config = LayoutConfig()
    public var animationEnabled = true
    public var scrollAnimationDuration: TimeInterval = 0.2

    /// Override to bypass NSEvent.mouseLocation-based monitor detection in tests
    public var activeMonitorOverride: Int?

    private convenience init() {
        self.init(
            logger: Logger.shared,
            windowEnumerator: WindowEnumerator.shared,
            windowController: WindowController.shared,
            animationController: AnimationController.shared
        )
    }

    public init(
        logger: Logging,
        windowEnumerator: WindowEnumerating,
        windowController: WindowManipulating,
        animationController: AnimationController = .shared
    ) {
        self.logger = logger
        self.windowEnumerator = windowEnumerator
        self.windowController = windowController
        self.animationController = animationController
    }
    
    // MARK: - Initialization
    
    private func assertMainThread(_ fn: String = #function) {
        assert(Thread.isMainThread, "LayoutEngine.\(fn) must be called from main thread")
    }

    public func start() {
        assertMainThread()
        logger.info("Layout engine starting...")
        
        // Enumerate monitors
        refreshMonitors()
        
        // Discover existing windows
        discoverWindows()
        
        // Apply initial layout
        applyLayout()
        
        logger.info("Layout engine ready with \(monitors.count) monitor(s), \(windowRegistry.count) window(s)")
    }
    
    public func stop() {
        assertMainThread()
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
            if let monitor = monitors.first,
               let monitorIndex = monitors.firstIndex(where: { $0.id == monitor.id }) {
                addWindowToWorkspace(window.id, monitor: monitorIndex)
            }
        }
    }
    
    func addWindowToWorkspace(_ windowID: WindowID, monitor monitorIndex: Int) {
        guard monitorIndex < monitors.count else { return }
        
        var ws = monitors[monitorIndex].activeWorkspace
        
        // Create a new column for this window
        let column = Column(windowIDs: [windowID], width: config.defaultWidth)
        
        // Insert the new column AFTER the currently focused column (if any)
        // This makes new windows appear next to existing ones logically
        let insertionIndex: Int
        if ws.columns.isEmpty {
            insertionIndex = 0
        } else if ws.focusedColumnIndex < ws.columns.count {
            // Insert after focused column
            insertionIndex = ws.focusedColumnIndex + 1
        } else {
            // Fallback: append at end
            insertionIndex = ws.columns.count
        }
        
        ws.columns.insert(column, at: insertionIndex)
        
        // Focus the new window
        ws.focusedColumnIndex = insertionIndex
        ws.focusedWindowIndex = 0
        
        monitors[monitorIndex].activeWorkspace = ws
        
        logger.info("Added window \(windowID) to monitor \(monitorIndex), column \(insertionIndex) (inserted after focused)")
    }
    
    // MARK: - Layout Calculation
    
    /// Calculate target frames for all windows in a workspace
    public func calculateLayout(for workspace: Workspace, in frame: CGRect) -> [(WindowID, CGRect)] {
        var results: [(WindowID, CGRect)] = []
        var x = config.outerGaps.left - workspace.scrollOffset
        let usableHeight = frame.height - config.outerGaps.top - config.outerGaps.bottom
        let usableWidth = frame.width - config.outerGaps.left - config.outerGaps.right
        
        for (_, column) in workspace.columns.enumerated() {
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
    public func applyLayout() {
        assertMainThread()
        for monitor in monitors {
            let layout = calculateLayout(for: monitor.activeWorkspace, in: monitor.frame)
            
            for (windowID, frame) in layout {
                // Only move windows that are on-screen (visible in viewport)
                let viewportLeft = monitor.frame.origin.x
                let viewportRight = monitor.frame.origin.x + monitor.frame.width
                
                if frame.maxX >= viewportLeft && frame.minX <= viewportRight {
                    // Window is at least partially visible
                    // CLIP the frame to monitor boundaries to prevent bleed-over
                    var clippedFrame = frame
                    
                    // Clip left edge
                    if clippedFrame.minX < viewportLeft {
                        let overhang = viewportLeft - clippedFrame.minX
                        clippedFrame.origin.x = viewportLeft
                        clippedFrame.size.width -= overhang
                    }
                    
                    // Clip right edge
                    if clippedFrame.maxX > viewportRight {
                        clippedFrame.size.width = viewportRight - clippedFrame.origin.x
                    }
                    
                    // Only apply if window still has reasonable width
                    if clippedFrame.width >= Constants.minimumWindowWidth {
                        if !windowController.setWindowFrame(windowID, frame: clippedFrame) {
                            logger.debug("Failed to set frame for window \(windowID)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Focus Operations

    public func focusColumnFirst() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        var ws = monitors[monitorIdx].activeWorkspace
        guard !ws.columns.isEmpty else { return }
        ws.focusedColumnIndex = 0
        ws.focusedWindowIndex = 0
        monitors[monitorIdx].activeWorkspace = ws
        scrollToFocus(monitorIndex: monitorIdx)
        if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
            _ = windowController.focusWindow(windowID)
        }
    }

    public func focusColumnLast() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        var ws = monitors[monitorIdx].activeWorkspace
        guard !ws.columns.isEmpty else { return }
        ws.focusedColumnIndex = ws.columns.count - 1
        ws.focusedWindowIndex = 0
        monitors[monitorIdx].activeWorkspace = ws
        scrollToFocus(monitorIndex: monitorIdx)
        if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
            _ = windowController.focusWindow(windowID)
        }
    }

    public func focusColumnLeft() {
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
    
    public func focusColumnRight() {
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
    
    public func focusWindowUp() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumn != nil, ws.focusedWindowIndex > 0 else { return }
        
        ws.focusedWindowIndex -= 1
        monitors[monitorIdx].activeWorkspace = ws
        
        if let windowID = monitors[monitorIdx].activeWorkspace.focusedWindowID {
            _ = windowController.focusWindow(windowID)
        }
    }
    
    public func focusWindowDown() {
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
    
    public func moveColumnLeft() {
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
    
    public func moveColumnRight() {
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
    
    public func consumeWindowIntoColumn() {
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
    
    public func expelWindowFromColumn() {
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
    
    // MARK: - Split Group Operations
    
    /// Create a split group from the focused column
    /// This converts a column with multiple windows into a centered split group
    public func createSplitGroup(_ layout: SplitGroupLayout) {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count else { return }
        
        let column = ws.columns[ws.focusedColumnIndex]
        let requiredCount: Int
        switch layout {
        case .horizontal, .vertical: requiredCount = 2
        case .quad: requiredCount = 4
        }
        
        // If current column doesn't have enough windows, consume from adjacent columns
        var windowsForSplit: [WindowID] = Array(column.windowIDs.prefix(requiredCount))
        
        // Try to get more windows from next columns if needed
        var nextColIdx = ws.focusedColumnIndex + 1
        while windowsForSplit.count < requiredCount && nextColIdx < ws.columns.count {
            let needed = requiredCount - windowsForSplit.count
            let available = ws.columns[nextColIdx].windowIDs.prefix(needed)
            windowsForSplit.append(contentsOf: available)
            
            // Remove consumed windows from next column
            for _ in 0..<available.count {
                ws.columns[nextColIdx].windowIDs.removeFirst()
            }
            
            // Remove empty column
            if ws.columns[nextColIdx].isEmpty {
                ws.columns.remove(at: nextColIdx)
            } else {
                nextColIdx += 1
            }
        }
        
        guard windowsForSplit.count >= 2 else {
            logger.info("Not enough windows to create split group (need at least 2)")
            return
        }
        
        // Update current column with split group windows
        ws.columns[ws.focusedColumnIndex].windowIDs = windowsForSplit
        
        // Set width to full screen for centered view
        ws.columns[ws.focusedColumnIndex].width = .proportion(1.0)
        
        monitors[monitorIdx].activeWorkspace = ws
        
        logger.info("Created \(layout.rawValue) split group with \(windowsForSplit.count) windows")
        
        // Apply special split layout
        applySplitLayout(monitorIndex: monitorIdx, columnIndex: ws.focusedColumnIndex, layout: layout)
    }
    
    /// Apply split group layout to windows in a column
    private func applySplitLayout(monitorIndex: Int, columnIndex: Int, layout: SplitGroupLayout) {
        let monitor = monitors[monitorIndex]
        let ws = monitor.activeWorkspace
        guard columnIndex < ws.columns.count else { return }
        let column = ws.columns[columnIndex]
        let frame = monitor.frame
        let gaps = config.gaps
        let outerGaps = config.outerGaps
        
        let usableWidth = frame.width - outerGaps.left - outerGaps.right
        let usableHeight = frame.height - outerGaps.top - outerGaps.bottom
        
        var windowFrames: [(WindowID, CGRect)] = []
        
        switch layout {
        case .horizontal:
            // 2 windows side by side
            let windowWidth = (usableWidth - gaps) / 2
            for (i, windowID) in column.windowIDs.prefix(2).enumerated() {
                let x = frame.origin.x + outerGaps.left + (CGFloat(i) * (windowWidth + gaps))
                let windowFrame = CGRect(
                    x: x,
                    y: frame.origin.y + outerGaps.top,
                    width: windowWidth,
                    height: usableHeight
                )
                windowFrames.append((windowID, windowFrame))
            }
            
        case .vertical:
            // 2 windows stacked
            let windowHeight = (usableHeight - gaps) / 2
            for (i, windowID) in column.windowIDs.prefix(2).enumerated() {
                let y = frame.origin.y + outerGaps.top + (CGFloat(i) * (windowHeight + gaps))
                let windowFrame = CGRect(
                    x: frame.origin.x + outerGaps.left,
                    y: y,
                    width: usableWidth,
                    height: windowHeight
                )
                windowFrames.append((windowID, windowFrame))
            }
            
        case .quad:
            // 4 windows in 2x2 grid
            let windowWidth = (usableWidth - gaps) / 2
            let windowHeight = (usableHeight - gaps) / 2
            let positions: [(Int, Int)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
            
            for (i, windowID) in column.windowIDs.prefix(4).enumerated() {
                let (col, row) = positions[i]
                let x = frame.origin.x + outerGaps.left + (CGFloat(col) * (windowWidth + gaps))
                let y = frame.origin.y + outerGaps.top + (CGFloat(row) * (windowHeight + gaps))
                let windowFrame = CGRect(x: x, y: y, width: windowWidth, height: windowHeight)
                windowFrames.append((windowID, windowFrame))
            }
        }
        
        // Apply the frames
        for (windowID, windowFrame) in windowFrames {
            _ = windowController.setWindowFrame(windowID, frame: windowFrame)
        }
    }
    
    // MARK: - Size Operations
    
    public func switchPresetColumnWidth() {
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
    
    public func centerColumn() {
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
    
    public func maximizeColumn() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count else { return }
        
        ws.columns[ws.focusedColumnIndex].width = .proportion(1.0)
        monitors[monitorIdx].activeWorkspace = ws
        applyLayout()
    }
    
    public func setColumnWidth(_ widthSpec: String) {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count else { return }
        
        let monitor = monitors[monitorIdx]
        let usableWidth = monitor.frame.width - config.outerGaps.left - config.outerGaps.right
        
        // Parse width spec: "+10%", "-50", "0.5", "500"
        var spec = widthSpec.trimmingCharacters(in: .whitespaces)
        let isRelative = spec.hasPrefix("+") || spec.hasPrefix("-")
        let isPercent = spec.hasSuffix("%")
        
        if isPercent {
            spec = String(spec.dropLast())
        }
        
        guard let value = Double(spec) else {
            logger.error("Invalid width spec: \(widthSpec)")
            return
        }
        
        let currentWidth = ws.columns[ws.focusedColumnIndex].width.resolve(in: usableWidth, gaps: config.gaps)
        
        let newWidth: ColumnWidth
        if isPercent {
            let proportion = CGFloat(value) / 100.0
            if isRelative {
                let currentProportion = currentWidth / usableWidth
                newWidth = .proportion(max(0.1, min(1.0, currentProportion + proportion)))
            } else {
                newWidth = .proportion(max(0.1, min(1.0, proportion)))
            }
        } else {
            let pixels = CGFloat(value)
            if isRelative {
                newWidth = .fixed(max(100, currentWidth + pixels))
            } else {
                newWidth = .fixed(max(100, pixels))
            }
        }
        
        ws.columns[ws.focusedColumnIndex].width = newWidth
        monitors[monitorIdx].activeWorkspace = ws
        applyLayout()
    }
    
    public func toggleFullscreen() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        let ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count else { return }
        
        let currentWidth = ws.columns[ws.focusedColumnIndex].width
        
        // Toggle between current width and 100%
        if case .proportion(let p) = currentWidth, p >= 0.99 {
            // Currently maximized, restore to default
            monitors[monitorIdx].activeWorkspace.columns[ws.focusedColumnIndex].width = config.defaultWidth
        } else {
            // Maximize
            monitors[monitorIdx].activeWorkspace.columns[ws.focusedColumnIndex].width = .proportion(1.0)
        }
        
        applyLayout()
    }
    
    // MARK: - Move Window Within Column
    
    public func moveWindowUp() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count,
              ws.focusedWindowIndex > 0 else { return }
        
        let idx = ws.focusedWindowIndex
        ws.columns[ws.focusedColumnIndex].windowIDs.swapAt(idx, idx - 1)
        ws.focusedWindowIndex -= 1
        monitors[monitorIdx].activeWorkspace = ws
        
        applyLayout()
    }
    
    public func moveWindowDown() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard ws.focusedColumnIndex < ws.columns.count,
              ws.focusedWindowIndex < ws.columns[ws.focusedColumnIndex].windowIDs.count - 1 else { return }
        
        let idx = ws.focusedWindowIndex
        ws.columns[ws.focusedColumnIndex].windowIDs.swapAt(idx, idx + 1)
        ws.focusedWindowIndex += 1
        monitors[monitorIdx].activeWorkspace = ws
        
        applyLayout()
    }
    
    // MARK: - Workspace Operations
    
    public func workspaceUp() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        let currentIdx = monitors[monitorIdx].activeWorkspaceIndex
        if currentIdx > 0 {
            monitors[monitorIdx].activeWorkspaceIndex = currentIdx - 1
            logger.info("Switched to workspace \(monitors[monitorIdx].activeWorkspaceIndex + 1)")
            applyLayout()
        }
    }
    
    public func workspaceDown() {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        let currentIdx = monitors[monitorIdx].activeWorkspaceIndex
        
        // Create new workspace if needed
        if currentIdx >= monitors[monitorIdx].workspaces.count - 1 {
            let newWorkspace = Workspace(id: monitors[monitorIdx].workspaces.count + 1)
            monitors[monitorIdx].workspaces.append(newWorkspace)
        }
        
        monitors[monitorIdx].activeWorkspaceIndex = currentIdx + 1
        logger.info("Switched to workspace \(monitors[monitorIdx].activeWorkspaceIndex + 1)")
        applyLayout()
    }
    
    /// Create a new workspace BELOW the current one and switch to it
    public func createWorkspaceBelow() {
        guard let (monitorIdx, _) = getActiveContext() else {
            logger.error("createWorkspaceBelow: No active context!")
            return
        }
        
        let currentIdx = monitors[monitorIdx].activeWorkspaceIndex
        let totalBefore = monitors[monitorIdx].workspaces.count
        
        logger.info("Creating workspace BELOW: monitor=\(monitorIdx), currentWS=\(currentIdx + 1), totalBefore=\(totalBefore)")
        
        // Create new workspace and insert it after current
        let newWorkspace = Workspace(id: 0)  // ID will be reassigned
        monitors[monitorIdx].workspaces.insert(newWorkspace, at: currentIdx + 1)
        
        // Reassign workspace IDs to maintain order
        for i in monitors[monitorIdx].workspaces.indices {
            monitors[monitorIdx].workspaces[i] = Workspace(
                id: i + 1,
                columns: monitors[monitorIdx].workspaces[i].columns,
                scrollOffset: monitors[monitorIdx].workspaces[i].scrollOffset,
                focusedColumnIndex: monitors[monitorIdx].workspaces[i].focusedColumnIndex,
                focusedWindowIndex: monitors[monitorIdx].workspaces[i].focusedWindowIndex
            )
        }
        
        // Switch to the new workspace
        monitors[monitorIdx].activeWorkspaceIndex = currentIdx + 1
        logger.info("✓ Created workspace below! Now on workspace \(currentIdx + 2) of \(monitors[monitorIdx].workspaces.count)")
        applyLayout()
    }
    
    /// Create a new workspace ABOVE the current one and switch to it
    public func createWorkspaceAbove() {
        guard let (monitorIdx, _) = getActiveContext() else {
            logger.error("createWorkspaceAbove: No active context!")
            return
        }
        
        let currentIdx = monitors[monitorIdx].activeWorkspaceIndex
        let totalBefore = monitors[monitorIdx].workspaces.count
        
        logger.info("Creating workspace ABOVE: monitor=\(monitorIdx), currentWS=\(currentIdx + 1), totalBefore=\(totalBefore)")
        
        // Create new workspace and insert it before current
        let newWorkspace = Workspace(id: 0)  // ID will be reassigned
        monitors[monitorIdx].workspaces.insert(newWorkspace, at: currentIdx)
        
        // Reassign workspace IDs to maintain order
        for i in monitors[monitorIdx].workspaces.indices {
            monitors[monitorIdx].workspaces[i] = Workspace(
                id: i + 1,
                columns: monitors[monitorIdx].workspaces[i].columns,
                scrollOffset: monitors[monitorIdx].workspaces[i].scrollOffset,
                focusedColumnIndex: monitors[monitorIdx].workspaces[i].focusedColumnIndex,
                focusedWindowIndex: monitors[monitorIdx].workspaces[i].focusedWindowIndex
            )
        }
        
        // Stay on the same index (which is now the new workspace)
        // currentIdx now points to the new workspace since we inserted before it
        logger.info("✓ Created workspace above! Now on workspace \(currentIdx + 1) of \(monitors[monitorIdx].workspaces.count)")
        applyLayout()
    }
    
    public func focusWorkspace(_ index: Int) {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        // Ensure workspace exists (1-indexed from user)
        let wsIndex = index - 1
        guard wsIndex >= 0 else { return }
        
        while monitors[monitorIdx].workspaces.count <= wsIndex {
            let newWorkspace = Workspace(id: monitors[monitorIdx].workspaces.count + 1)
            monitors[monitorIdx].workspaces.append(newWorkspace)
        }
        
        monitors[monitorIdx].activeWorkspaceIndex = wsIndex
        logger.info("Focused workspace \(index)")
        applyLayout()
    }
    
    public func moveWindowToWorkspace(_ index: Int) {
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        var ws = monitors[monitorIdx].activeWorkspace
        guard let windowID = ws.focusedWindowID,
              ws.focusedColumnIndex < ws.columns.count else { return }
        
        // Remove window from current column
        ws.columns[ws.focusedColumnIndex].windowIDs.remove(at: ws.focusedWindowIndex)
        
        // Remove empty column
        if ws.columns[ws.focusedColumnIndex].isEmpty {
            ws.columns.remove(at: ws.focusedColumnIndex)
            if ws.focusedColumnIndex > 0 {
                ws.focusedColumnIndex -= 1
            }
        }
        ws.focusedWindowIndex = 0
        monitors[monitorIdx].activeWorkspace = ws
        
        // Ensure target workspace exists (1-indexed)
        let targetIdx = index - 1
        guard targetIdx >= 0 else { return }
        
        while monitors[monitorIdx].workspaces.count <= targetIdx {
            let newWorkspace = Workspace(id: monitors[monitorIdx].workspaces.count + 1)
            monitors[monitorIdx].workspaces.append(newWorkspace)
        }
        
        // Add window to target workspace
        let newColumn = Column(windowIDs: [windowID], width: config.defaultWidth)
        monitors[monitorIdx].workspaces[targetIdx].columns.append(newColumn)
        
        logger.info("Moved window \(windowID) to workspace \(index)")
        applyLayout()
    }
    
    // MARK: - Scroll Operations
    
    public func scroll(by delta: CGFloat) {
        assertMainThread()
        guard let (monitorIdx, _) = getActiveContext() else { return }
        
        monitors[monitorIdx].activeWorkspace.scrollOffset += delta
        applyLayout()
    }
    
    /// Animate scroll to a specific offset
    private func animateScrollTo(_ targetOffset: CGFloat, monitorIndex: Int) {
        guard animationEnabled else {
            monitors[monitorIndex].activeWorkspace.scrollOffset = targetOffset
            applyLayout()
            return
        }
        
        // Cancel any existing animation
        scrollAnimationTimer?.invalidate()
        
        let startOffset = monitors[monitorIndex].activeWorkspace.scrollOffset
        let distance = targetOffset - startOffset
        
        // Skip animation for small movements
        if abs(distance) < Constants.minimumScrollDelta {
            monitors[monitorIndex].activeWorkspace.scrollOffset = targetOffset
            applyLayout()
            return
        }
        
        isAnimatingScroll = true
        targetScrollOffset = targetOffset
        
        let startTime = CACurrentMediaTime()
        let duration = scrollAnimationDuration
        
        scrollAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            
            // Ease-out cubic for smooth deceleration
            let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
            
            let currentOffset = startOffset + (distance * CGFloat(easedProgress))
            self.monitors[monitorIndex].activeWorkspace.scrollOffset = currentOffset
            self.applyLayout()
            
            if progress >= 1.0 {
                timer.invalidate()
                self.scrollAnimationTimer = nil
                self.isAnimatingScroll = false
                // Ensure we land exactly on target
                self.monitors[monitorIndex].activeWorkspace.scrollOffset = targetOffset
                self.applyLayout()
            }
        }
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
            // Use animated scroll for smooth transition
            animateScrollTo(newOffset, monitorIndex: monitorIndex)
        }
    }
    
    // MARK: - Window Management
    
    /// Add a newly discovered window to the layout
    public func addWindow(_ windowID: WindowID) {
        assertMainThread()
        // Check if already tracked
        guard windowRegistry[windowID] == nil else { return }
        
        // Get window info
        guard let window = windowEnumerator.getWindow(id: windowID) else { return }
        
        windowRegistry[windowID] = window
        
        // Determine which monitor to place the window on:
        // 1. Prefer the monitor where the mouse cursor is (user's active monitor)
        // 2. Fallback to monitor containing the window's center
        var targetMonitorIdx = 0
        
        let mouseLocation = NSEvent.mouseLocation
        for (idx, monitor) in monitors.enumerated() {
            if monitor.frame.contains(mouseLocation) {
                targetMonitorIdx = idx
                break
            }
        }
        
        // Alternative: use window position if mouse-based selection didn't work
        if targetMonitorIdx == 0 && monitors.count > 1 {
            let windowCenter = CGPoint(
                x: window.frame.midX,
                y: window.frame.midY
            )
            for (idx, monitor) in monitors.enumerated() {
                if monitor.frame.contains(windowCenter) {
                    targetMonitorIdx = idx
                    break
                }
            }
        }
        
        logger.info("New window \(windowID) (\(window.appName)) - placing on monitor \(targetMonitorIdx)")
        
        addWindowToWorkspace(windowID, monitor: targetMonitorIdx)
        
        // Scroll to show the new window
        scrollToFocus(monitorIndex: targetMonitorIdx)
        applyLayout()
    }
    
    /// Remove a window from the layout
    public func removeWindow(_ windowID: WindowID) {
        assertMainThread()
        windowRegistry.removeValue(forKey: windowID)
        floatingWindows.remove(windowID)
        
        // Remove from all workspaces
        for i in monitors.indices {
            for j in monitors[i].workspaces.indices {
                for k in monitors[i].workspaces[j].columns.indices.reversed() {
                    monitors[i].workspaces[j].columns[k].windowIDs.removeAll { $0 == windowID }
                    if monitors[i].workspaces[j].columns[k].isEmpty {
                        monitors[i].workspaces[j].columns.remove(at: k)
                    }
                }
            }
        }
        
        applyLayout()
    }
    
    /// Sync focus state when a window is focused externally
    public func syncFocus(to windowID: WindowID) {
        // Find the window in our layout
        for (mi, monitor) in monitors.enumerated() {
            for (wi, workspace) in monitor.workspaces.enumerated() {
                for (ci, column) in workspace.columns.enumerated() {
                    if let windowIdx = column.windowIDs.firstIndex(of: windowID) {
                        // Switch to this workspace and focus
                        monitors[mi].activeWorkspaceIndex = wi
                        monitors[mi].activeWorkspace.focusedColumnIndex = ci
                        monitors[mi].activeWorkspace.focusedWindowIndex = windowIdx
                        scrollToFocus(monitorIndex: mi)
                        return
                    }
                }
            }
        }
    }
    
    /// Refresh window list and layout
    public func refresh() {
        discoverWindows()
        applyLayout()
    }
    
    // MARK: - Query Operations
    
    /// Get list of all windows for debugging
    public func listWindows() -> [[String: Any]] {
        var result: [[String: Any]] = []
        
        for (mi, monitor) in monitors.enumerated() {
            let ws = monitor.activeWorkspace
            for (ci, column) in ws.columns.enumerated() {
                for (wi, windowID) in column.windowIDs.enumerated() {
                    let window = windowRegistry[windowID]
                    let isFocused = ci == ws.focusedColumnIndex && wi == ws.focusedWindowIndex
                    
                    result.append([
                        "id": windowID,
                        "app": window?.appName ?? "Unknown",
                        "title": window?.title ?? "",
                        "column": ci,
                        "index": wi,
                        "focused": isFocused,
                        "monitor": mi,
                        "workspace": monitor.activeWorkspaceIndex + 1
                    ])
                }
            }
        }
        
        return result
    }
    
    /// Get current status for debugging
    public func getStatus() -> [String: Any] {
        guard let (monitorIdx, _) = getActiveContext() else {
            return ["error": "No monitors"]
        }
        
        let monitor = monitors[monitorIdx]
        let ws = monitor.activeWorkspace
        
        // Build monitor info
        var monitorInfo: [[String: Any]] = []
        for (idx, m) in monitors.enumerated() {
            monitorInfo.append([
                "index": idx,
                "displayID": m.displayID,
                "frame": "\(Int(m.frame.origin.x)),\(Int(m.frame.origin.y)) \(Int(m.frame.width))x\(Int(m.frame.height))",
                "workspaces": m.workspaces.count,
                "activeWorkspace": m.activeWorkspaceIndex + 1,
                "columns": m.activeWorkspace.columns.count
            ])
        }
        
        return [
            "monitors": monitors.count,
            "activeMonitor": monitorIdx,
            "monitorDetails": monitorInfo,
            "workspace": ws.id,
            "workspaceCount": monitor.workspaces.count,
            "columns": ws.columns.count,
            "focusedColumn": ws.focusedColumnIndex,
            "focusedWindow": ws.focusedWindowIndex,
            "focusedWindowID": ws.focusedWindowID ?? 0,
            "scrollOffset": ws.scrollOffset,
            "totalWindows": windowRegistry.count
        ]
    }
    
    // MARK: - Helpers
    
    /// Get current active monitor and workspace indices based on mouse position
    func getActiveContext() -> (Int, Int)? {
        guard !monitors.isEmpty else { return nil }

        // Test override: skip mouse-based detection
        if let override = activeMonitorOverride {
            guard override < monitors.count else { return nil }
            return (override, monitors[override].activeWorkspaceIndex)
        }

        // Get current mouse location
        let mouseLocation = NSEvent.mouseLocation

        // Find which monitor contains the mouse
        for (index, monitor) in monitors.enumerated() {
            if monitor.frame.contains(mouseLocation) {
                return (index, monitor.activeWorkspaceIndex)
            }
        }

        // Fallback: use primary monitor (index 0)
        return (0, monitors[0].activeWorkspaceIndex)
    }
    
    /// Get monitor index for a specific display ID
    public func getMonitorIndex(for displayID: CGDirectDisplayID) -> Int? {
        return monitors.firstIndex(where: { $0.displayID == displayID })
    }
    
    /// Get monitor index at a specific screen point
    public func getMonitorIndex(at point: CGPoint) -> Int? {
        for (index, monitor) in monitors.enumerated() {
            if monitor.frame.contains(point) {
                return index
            }
        }
        return nil
    }
    
    /// Debug: print current state
    public func debugPrint() {
        logger.info("=== Layout State ===")
        for (i, monitor) in monitors.enumerated() {
            logger.info("Monitor \(i): \(monitor.frame)")
            let ws = monitor.activeWorkspace
            logger.info("  Workspace \(ws.id): scroll=\(ws.scrollOffset), focus=(\(ws.focusedColumnIndex), \(ws.focusedWindowIndex))")
            for (j, col) in ws.columns.enumerated() {
                logger.info("    Column \(j): \(col.windowIDs.count) windows, width=\(col.width)")
                for windowID in col.windowIDs {
                    let window = windowRegistry[windowID]
                    logger.info("      - \(windowID): \(window?.appName ?? "?") - \(window?.title ?? "")")
                }
            }
        }
    }
}
