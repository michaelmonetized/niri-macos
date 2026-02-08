import Foundation
import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger.shared
    private let layoutEngine = LayoutEngine.shared
    private let ipcServer = IPCServer.shared
    private let gestureRecognizer = GestureRecognizer.shared
    private let axObserver = AXWindowObserver.shared
    
    private var statusItem: NSStatusItem?
    private var windowObserver: WindowObserver?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("========================================")
        logger.info("niri-macos starting...")
        logger.info("========================================")
        
        // Check accessibility permissions
        let hasPermissions = WindowEnumerator.shared.checkAccessibilityPermissions()
        if !hasPermissions {
            logger.error("Accessibility permissions required!")
            logger.info("Please grant access in System Preferences → Privacy & Security → Accessibility")
            // Continue anyway - it will prompt the user
        }
        
        // Start layout engine
        layoutEngine.start()
        
        // Start IPC server
        ipcServer.start()
        
        // Start AX observer and wire callbacks
        setupAXObserver()
        
        // Start gesture recognizer and wire to layout engine
        setupGestureRecognizer()
        
        // Start observing workspace/app changes
        windowObserver = WindowObserver()
        windowObserver?.start()
        
        // Setup menubar
        setupMenubar()
        
        logger.info("niri-macos ready")
        logger.info("IPC socket: /tmp/niri-macos.sock")
        logger.info("Use 'niri-msg help' for available commands")
        
        // Debug print initial state
        layoutEngine.debugPrint()
    }
    
    private func setupAXObserver() {
        // Wire AX observer callbacks to layout engine
        axObserver.onWindowCreated = { [weak self] windowID, pid in
            self?.logger.debug("AX: Window created \(windowID) (pid \(pid))")
            self?.layoutEngine.addWindow(windowID)
        }
        
        axObserver.onWindowDestroyed = { [weak self] windowID, pid in
            self?.logger.debug("AX: Window destroyed (pid \(pid))")
            // Refresh layout to clean up orphaned windows
            self?.layoutEngine.refresh()
        }
        
        axObserver.onWindowFocused = { [weak self] windowID in
            self?.logger.debug("AX: Window focused \(windowID)")
            self?.layoutEngine.syncFocus(to: windowID)
        }
        
        axObserver.onWindowMoved = { [weak self] windowID, frame in
            self?.logger.debug("AX: Window moved \(windowID) to \(frame)")
            // For now, we don't react to external moves (we're controlling positions)
        }
        
        axObserver.onWindowResized = { [weak self] windowID, frame in
            self?.logger.debug("AX: Window resized \(windowID) to \(frame)")
            // For now, we don't react to external resizes
        }
        
        axObserver.onWindowMinimized = { [weak self] windowID, minimized in
            self?.logger.debug("AX: Window \(windowID) minimized=\(minimized)")
            if minimized {
                self?.layoutEngine.removeWindow(windowID)
            }
        }
        
        axObserver.start()
    }
    
    private func setupGestureRecognizer() {
        // Wire gesture recognizer to layout engine for scrolling
        gestureRecognizer.onScroll = { [weak self] delta in
            // Invert delta for natural scrolling (swipe left = scroll right)
            self?.layoutEngine.scroll(by: -delta)
        }
        
        gestureRecognizer.onScrollBegan = { [weak self] in
            self?.logger.debug("Gesture: Scroll began")
        }
        
        gestureRecognizer.onScrollEnded = { [weak self] in
            self?.logger.debug("Gesture: Scroll ended")
        }
        
        // Discrete scroll callbacks (Cmd+Shift+scroll for windows)
        gestureRecognizer.onFocusWindowLeft = { [weak self] in
            self?.logger.debug("Gesture: Focus window left")
            self?.layoutEngine.focusColumnLeft()
        }
        
        gestureRecognizer.onFocusWindowRight = { [weak self] in
            self?.logger.debug("Gesture: Focus window right")
            self?.layoutEngine.focusColumnRight()
        }
        
        // Discrete scroll callbacks (Cmd+scroll for workspaces)
        gestureRecognizer.onWorkspaceUp = { [weak self] in
            self?.logger.debug("Gesture: Workspace up")
            self?.layoutEngine.workspaceUp()
        }
        
        gestureRecognizer.onWorkspaceDown = { [weak self] in
            self?.logger.debug("Gesture: Workspace down")
            self?.layoutEngine.workspaceDown()
        }
        
        gestureRecognizer.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("========================================")
        logger.info("niri-macos shutting down...")
        logger.info("========================================")
        
        gestureRecognizer.stop()
        axObserver.stop()
        windowObserver?.stop()
        ipcServer.stop()
        layoutEngine.stop()
        
        logger.info("niri-macos shutdown complete")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "📜"  // Scroll emoji for niri
        }
        
        let menu = NSMenu()
        
        // Status
        let statusLabel = NSMenuItem(title: "niri-macos running", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        
        menu.addItem(NSMenuItem.separator())
        
        // Layout actions (for testing without skhd)
        menu.addItem(NSMenuItem(title: "← Focus Left", action: #selector(focusLeft), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "→ Focus Right", action: #selector(focusRight), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "↑ Focus Up", action: #selector(focusUp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "↓ Focus Down", action: #selector(focusDown), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⇐ Move Column Left", action: #selector(moveLeft), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⇒ Move Column Right", action: #selector(moveRight), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⬆ Move Window Up", action: #selector(moveWinUp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⬇ Move Window Down", action: #selector(moveWinDown), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⊕ Consume Window", action: #selector(consumeWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊖ Expel Window", action: #selector(expelWindow), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⟷ Cycle Width", action: #selector(cycleWidth), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊙ Center Column", action: #selector(centerColumn), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⬛ Toggle Fullscreen", action: #selector(toggleFullscreen), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "↑ Workspace Up", action: #selector(workspaceUp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "↓ Workspace Down", action: #selector(workspaceDown), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊕ Create Workspace Above", action: #selector(createWorkspaceAbove), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊕ Create Workspace Below", action: #selector(createWorkspaceBelow), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Split groups
        menu.addItem(NSMenuItem(title: "⬛⬛ Split Horizontal", action: #selector(splitHorizontal), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⬛/⬛ Split Vertical", action: #selector(splitVertical), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊞ Split Quad", action: #selector(splitQuad), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⟳ Refresh Layout", action: #selector(refreshLayout), keyEquivalent: "r"))
        
        menu.addItem(NSMenuItem.separator())
        
        let logItem = NSMenuItem(title: "View Log...", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        
        let debugItem = NSMenuItem(title: "Debug Print", action: #selector(debugPrint), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Set targets for all action items
        for item in menu.items {
            if item.action != nil && item.target == nil {
                item.target = self
            }
        }
        
        statusItem?.menu = menu
    }
    
    // MARK: - Menu Actions
    
    @objc private func focusLeft() { layoutEngine.focusColumnLeft() }
    @objc private func focusRight() { layoutEngine.focusColumnRight() }
    @objc private func focusUp() { layoutEngine.focusWindowUp() }
    @objc private func focusDown() { layoutEngine.focusWindowDown() }
    
    @objc private func moveLeft() { layoutEngine.moveColumnLeft() }
    @objc private func moveRight() { layoutEngine.moveColumnRight() }
    @objc private func moveWinUp() { layoutEngine.moveWindowUp() }
    @objc private func moveWinDown() { layoutEngine.moveWindowDown() }
    
    @objc private func consumeWindow() { layoutEngine.consumeWindowIntoColumn() }
    @objc private func expelWindow() { layoutEngine.expelWindowFromColumn() }
    
    @objc private func cycleWidth() { layoutEngine.switchPresetColumnWidth() }
    @objc private func centerColumn() { layoutEngine.centerColumn() }
    @objc private func toggleFullscreen() { layoutEngine.toggleFullscreen() }
    
    @objc private func workspaceUp() { layoutEngine.workspaceUp() }
    @objc private func workspaceDown() { layoutEngine.workspaceDown() }
    @objc private func createWorkspaceAbove() { layoutEngine.createWorkspaceAbove() }
    @objc private func createWorkspaceBelow() { layoutEngine.createWorkspaceBelow() }
    
    @objc private func splitHorizontal() { layoutEngine.createSplitGroup(.horizontal) }
    @objc private func splitVertical() { layoutEngine.createSplitGroup(.vertical) }
    @objc private func splitQuad() { layoutEngine.createSplitGroup(.quad) }
    
    @objc private func refreshLayout() { layoutEngine.refresh() }
    
    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/niri-macos.log"))
    }
    
    @objc private func debugPrint() {
        layoutEngine.debugPrint()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Window Observer

class WindowObserver {
    private let logger = Logger.shared
    private let layoutEngine = LayoutEngine.shared
    private var workspaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    
    func start() {
        // Observe application activation changes
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.logger.debug("App activated: \(app.localizedName ?? "Unknown")")
            }
        }
        
        // Observe space changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.debug("Active space changed")
            // TODO: Refresh layout for new space
        }
        
        logger.info("Window observer started")
    }
    
    func stop() {
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        logger.info("Window observer stopped")
    }
}

// MARK: - Signal Handling

func setupSignalHandlers() {
    signal(SIGINT) { _ in
        Logger.shared.info("Received SIGINT")
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
    
    signal(SIGTERM) { _ in
        Logger.shared.info("Received SIGTERM")
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Main

setupSignalHandlers()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
