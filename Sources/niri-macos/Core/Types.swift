import Foundation
import CoreGraphics

// MARK: - Window Types

typealias WindowID = CGWindowID

struct WindowInfo: Identifiable, Equatable {
    let id: WindowID
    let ownerPID: pid_t
    let bundleID: String?
    let appName: String
    var title: String
    var frame: CGRect
    var space: Int
    var isOnScreen: Bool
    var isMinimized: Bool
    var layer: Int32
    
    var isStandardWindow: Bool {
        layer == 0  // kCGNormalWindowLevel
    }
}

// MARK: - Layout Types

enum ColumnWidth: Equatable {
    case proportion(CGFloat)  // 0.0 - 1.0
    case fixed(CGFloat)       // Pixels
    
    static let presets: [ColumnWidth] = [
        .proportion(0.33),
        .proportion(0.5),
        .proportion(0.66),
        .proportion(1.0)
    ]
    
    func resolve(in availableWidth: CGFloat, gaps: CGFloat) -> CGFloat {
        switch self {
        case .proportion(let p):
            return (availableWidth - gaps) * p
        case .fixed(let w):
            return w
        }
    }
}

struct Column: Identifiable {
    let id = UUID()
    var windowIDs: [WindowID]
    var width: ColumnWidth
    
    var isEmpty: Bool { windowIDs.isEmpty }
    var windowCount: Int { windowIDs.count }
}

struct Workspace: Identifiable {
    let id: Int
    var columns: [Column]
    var scrollOffset: CGFloat  // X position of viewport left edge in infinite strip
    var focusedColumnIndex: Int
    var focusedWindowIndex: Int  // Within focused column
    
    init(id: Int) {
        self.id = id
        self.columns = []
        self.scrollOffset = 0
        self.focusedColumnIndex = 0
        self.focusedWindowIndex = 0
    }
    
    var focusedColumn: Column? {
        guard focusedColumnIndex >= 0 && focusedColumnIndex < columns.count else { return nil }
        return columns[focusedColumnIndex]
    }
    
    var focusedWindowID: WindowID? {
        guard let col = focusedColumn,
              focusedWindowIndex >= 0 && focusedWindowIndex < col.windowIDs.count else { return nil }
        return col.windowIDs[focusedWindowIndex]
    }
}

struct Monitor: Identifiable {
    let id: UUID
    let displayID: CGDirectDisplayID
    var frame: CGRect
    var workspaces: [Workspace]
    var activeWorkspaceIndex: Int
    
    init(displayID: CGDirectDisplayID, frame: CGRect) {
        self.id = UUID()
        self.displayID = displayID
        self.frame = frame
        self.workspaces = [Workspace(id: 1)]
        self.activeWorkspaceIndex = 0
    }
    
    var activeWorkspace: Workspace {
        get { workspaces[activeWorkspaceIndex] }
        set { workspaces[activeWorkspaceIndex] = newValue }
    }
}

// MARK: - Animation Types

struct SpringConfig {
    var damping: CGFloat
    var stiffness: CGFloat
    var mass: CGFloat
    var epsilon: CGFloat
    
    static let `default` = SpringConfig(damping: 0.8, stiffness: 500, mass: 1.0, epsilon: 0.001)
    static let snappy = SpringConfig(damping: 0.9, stiffness: 800, mass: 1.0, epsilon: 0.001)
    static let smooth = SpringConfig(damping: 0.7, stiffness: 300, mass: 1.0, epsilon: 0.001)
}

struct Spring {
    var config: SpringConfig
    var position: CGFloat
    var velocity: CGFloat
    var target: CGFloat
    
    var isSettled: Bool {
        abs(position - target) < config.epsilon && abs(velocity) < config.epsilon
    }
    
    mutating func step(dt: TimeInterval) {
        let displacement = position - target
        let springForce = -config.stiffness * displacement
        let dampingForce = -config.damping * velocity * 2 * sqrt(config.stiffness * config.mass)
        let acceleration = (springForce + dampingForce) / config.mass
        
        velocity += acceleration * dt
        position += velocity * dt
        
        // Snap to target if close enough
        if isSettled {
            position = target
            velocity = 0
        }
    }
}

// MARK: - IPC Types

enum IPCCommand: String, Codable {
    case focusColumnLeft = "focus-column-left"
    case focusColumnRight = "focus-column-right"
    case focusColumnFirst = "focus-column-first"
    case focusColumnLast = "focus-column-last"
    case focusWindowUp = "focus-window-up"
    case focusWindowDown = "focus-window-down"
    
    case moveColumnLeft = "move-column-left"
    case moveColumnRight = "move-column-right"
    case moveWindowUp = "move-window-up"
    case moveWindowDown = "move-window-down"
    
    case consumeWindow = "consume-window-into-column"
    case expelWindow = "expel-window-from-column"
    
    case centerColumn = "center-column"
    case maximizeColumn = "maximize-column"
    case switchPresetWidth = "switch-preset-column-width"
    
    case focusWorkspace = "focus-workspace"
    case moveToWorkspace = "move-window-to-workspace"
    
    case quit = "quit"
}

struct IPCRequest: Codable {
    let command: String
    let args: [String: String]?
}

struct IPCResponse: Codable {
    let success: Bool
    let error: String?
    let data: [String: String]?
}

// MARK: - Config Types

struct LayoutConfig {
    var gaps: CGFloat = 16
    var outerGaps: EdgeInsets = EdgeInsets(top: 0, bottom: 0, left: 0, right: 0)
    var centerFocusedColumn: CenterMode = .never
    var presetWidths: [ColumnWidth] = ColumnWidth.presets
    var defaultWidth: ColumnWidth = .proportion(0.5)
    
    struct EdgeInsets {
        var top: CGFloat
        var bottom: CGFloat
        var left: CGFloat
        var right: CGFloat
    }
    
    enum CenterMode {
        case never
        case always
        case onOverflow
    }
}

struct AnimationConfig {
    var enabled: Bool = true
    var workspaceSwitch: SpringConfig = .default
    var horizontalMovement: SpringConfig = .snappy
    var windowResize: SpringConfig = .default
}

struct NiriConfig {
    var layout: LayoutConfig = LayoutConfig()
    var animation: AnimationConfig = AnimationConfig()
    var windowRules: [WindowRule] = []
}

struct WindowRule {
    enum Matcher {
        case appID(String)
        case titleContains(String)
        case titleRegex(String)
    }
    
    enum Action {
        case float
        case fixedWidth(CGFloat)
        case workspace(Int)
    }
    
    var matchers: [Matcher]
    var actions: [Action]
}
