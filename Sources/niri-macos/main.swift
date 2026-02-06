import Foundation
import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger.shared
    private let layoutEngine = LayoutEngine.shared
    private let ipcServer = IPCServer.shared
    
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
            logger.info("Please grant access in System Preferences → Security & Privacy → Accessibility")
            // Continue anyway - it will prompt the user
        }
        
        // Start layout engine
        layoutEngine.start()
        
        // Start IPC server
        ipcServer.start()
        
        // Start observing window changes
        windowObserver = WindowObserver()
        windowObserver?.start()
        
        // Setup menubar
        setupMenubar()
        
        logger.info("niri-macos ready")
        
        // Debug print initial state
        layoutEngine.debugPrint()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("========================================")
        logger.info("niri-macos shutting down...")
        logger.info("========================================")
        
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
        
        menu.addItem(NSMenuItem(title: "⇐ Move Left", action: #selector(moveLeft), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⇒ Move Right", action: #selector(moveRight), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⊕ Consume Window", action: #selector(consumeWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊖ Expel Window", action: #selector(expelWindow), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "⟷ Cycle Width", action: #selector(cycleWidth), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⊙ Center Column", action: #selector(centerColumn), keyEquivalent: ""))
        
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
    
    @objc private func consumeWindow() { layoutEngine.consumeWindowIntoColumn() }
    @objc private func expelWindow() { layoutEngine.expelWindowFromColumn() }
    
    @objc private func cycleWidth() { layoutEngine.switchPresetColumnWidth() }
    @objc private func centerColumn() { layoutEngine.centerColumn() }
    
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
