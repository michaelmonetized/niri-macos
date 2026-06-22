import Foundation
import CoreGraphics

// MARK: - Window Types

public typealias WindowID = CGWindowID

public enum Constants {
    // Frame matching
    public static let frameMatchTolerance: CGFloat = 5.0
    
    // Layout
    public static let minimumWindowWidth: CGFloat = 100.0
    public static let minimumColumnProportion: CGFloat = 0.1
    public static let maximizedProportionThreshold: CGFloat = 0.99
    
    // IPC / Socket
    public static let socketBufferSize: Int = 65536
    public static let defaultSocketPath = "/tmp/niri-macos.sock"
    public static let defaultLogPath = "/tmp/niri-macos.log"
    
    // Scroll
    public static let scrollAnimationDuration: TimeInterval = 0.2
    public static let minimumScrollDelta: CGFloat = 5.0
    
    // Animation
    public static let animationSettledThreshold: CGFloat = 0.5
    public static let animationFrameInterval: TimeInterval = 1.0 / 60.0
    
    // Gesture
    public static let scrollThreshold: CGFloat = 25.0
    public static let scrollResetDelay: TimeInterval = 0.25
    public static let triggerCooldown: TimeInterval = 0.15
    public static let scrollMultiplier: CGFloat = 1.5
    public static let momentumDecay: CGFloat = 0.95
    public static let minimumVelocity: CGFloat = 0.5
    public static let minimumScrollDeltaForCallback: CGFloat = 0.1
    
    // AX Observer
    public static let initialWindowScanDelay: TimeInterval = 0.1
}

public struct WindowInfo: Identifiable, Equatable {
    public let id: WindowID
    public let ownerPID: pid_t
    public let bundleID: String?
    public let appName: String
    public var title: String
    public var frame: CGRect
    public var space: Int
    public var isOnScreen: Bool
    public var isMinimized: Bool
    public var layer: Int32
    
    public var isStandardWindow: Bool {
        layer == 0  // kCGNormalWindowLevel
    }

    public var isSpaceKnown: Bool {
        space >= 0
    }
}

// MARK: - Layout Types

public enum ColumnWidth: Equatable, Codable {
    case proportion(CGFloat)  // 0.0 - 1.0
    case fixed(CGFloat)       // Pixels

    public static let presets: [ColumnWidth] = [
        .proportion(0.33),
        .proportion(0.5),
        .proportion(0.66),
        .proportion(1.0)
    ]

    public func resolve(in availableWidth: CGFloat, gaps: CGFloat) -> CGFloat {
        switch self {
        case .proportion(let p):
            return (availableWidth - gaps) * p
        case .fixed(let w):
            return w
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(CGFloat.self, forKey: .value)
        switch type {
        case "proportion": self = .proportion(value)
        case "fixed": self = .fixed(value)
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown ColumnWidth type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .proportion(let v):
            try container.encode("proportion", forKey: .type)
            try container.encode(v, forKey: .value)
        case .fixed(let v):
            try container.encode("fixed", forKey: .type)
            try container.encode(v, forKey: .value)
        }
    }
}

public struct Column: Identifiable {
    public let id = UUID()
    public var windowIDs: [WindowID]
    public var width: ColumnWidth
    
    public var isEmpty: Bool { windowIDs.isEmpty }
    public var windowCount: Int { windowIDs.count }
}

// MARK: - Split Group Types

public enum SplitGroupLayout: String, Codable {
    case horizontal   // 2 windows side by side (50/50)
    case vertical     // 2 windows stacked (50/50)
    case quad         // 4 windows in 2x2 grid (25% each)
}

public struct SplitGroup: Identifiable {
    public let id = UUID()
    public var layout: SplitGroupLayout
    public var windowIDs: [WindowID]  // 2 for horizontal/vertical, 4 for quad
    public var width: ColumnWidth     // Width of the entire split group in the layout
    
    public var isEmpty: Bool { windowIDs.isEmpty }
    public var requiredWindowCount: Int {
        switch layout {
        case .horizontal, .vertical: return 2
        case .quad: return 4
        }
    }
    public var isFull: Bool { windowIDs.count >= requiredWindowCount }
}

public struct Workspace: Identifiable {
    public var id: Int
    public var columns: [Column]
    public var scrollOffset: CGFloat  // X position of viewport left edge in infinite strip
    public var focusedColumnIndex: Int
    public var focusedWindowIndex: Int  // Within focused column
    
    public init(id: Int) {
        self.id = id
        self.columns = []
        self.scrollOffset = 0
        self.focusedColumnIndex = 0
        self.focusedWindowIndex = 0
    }
    
    public init(id: Int, columns: [Column], scrollOffset: CGFloat, focusedColumnIndex: Int, focusedWindowIndex: Int) {
        self.id = id
        self.columns = columns
        self.scrollOffset = scrollOffset
        self.focusedColumnIndex = focusedColumnIndex
        self.focusedWindowIndex = focusedWindowIndex
    }
    
    public var focusedColumn: Column? {
        guard focusedColumnIndex >= 0 && focusedColumnIndex < columns.count else { return nil }
        return columns[focusedColumnIndex]
    }
    
    public var focusedWindowID: WindowID? {
        guard let col = focusedColumn,
              focusedWindowIndex >= 0 && focusedWindowIndex < col.windowIDs.count else { return nil }
        return col.windowIDs[focusedWindowIndex]
    }
}

public struct Monitor: Identifiable {
    public let id: UUID
    public let displayID: CGDirectDisplayID
    public var frame: CGRect
    public var workspaces: [Workspace]
    public var activeWorkspaceIndex: Int
    
    public init(displayID: CGDirectDisplayID, frame: CGRect) {
        self.id = UUID()
        self.displayID = displayID
        self.frame = frame
        self.workspaces = [Workspace(id: 1)]
        self.activeWorkspaceIndex = 0
    }
    
    public var activeWorkspace: Workspace {
        get { workspaces[activeWorkspaceIndex] }
        set { workspaces[activeWorkspaceIndex] = newValue }
    }
}

// MARK: - Animation Types

public struct SpringConfig: Codable {
    public var damping: CGFloat
    public var stiffness: CGFloat
    public var mass: CGFloat
    public var epsilon: CGFloat

    public static let `default` = SpringConfig(damping: 0.8, stiffness: 500, mass: 1.0, epsilon: 0.001)
    public static let snappy = SpringConfig(damping: 0.9, stiffness: 800, mass: 1.0, epsilon: 0.001)
    public static let smooth = SpringConfig(damping: 0.7, stiffness: 300, mass: 1.0, epsilon: 0.001)
}

// MARK: - IPC Types

public enum IPCCommand: String, Codable {
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
    case setColumnWidth = "set-column-width"
    
    case scrollWorkspace = "scroll-workspace"
    
    case focusWorkspace = "focus-workspace"
    case moveToWorkspace = "move-window-to-workspace"
    case workspaceUp = "workspace-up"
    case workspaceDown = "workspace-down"
    case createWorkspaceAbove = "create-workspace-above"
    case createWorkspaceBelow = "create-workspace-below"
    
    case toggleFullscreen = "toggle-fullscreen"
    
    // Split groups
    case createSplitHorizontal = "create-split-horizontal"
    case createSplitVertical = "create-split-vertical"
    case createSplitQuad = "create-split-quad"
    
    case listWindows = "list-windows"
    case status = "status"
    
    case quit = "quit"
}

public struct IPCRequest: Codable {
    public let command: String
    public let args: [String: String]?
}

public struct IPCResponse: Codable {
    public let success: Bool
    public let error: String?
    public let data: [String: String]?
}

// MARK: - Config Types

public struct LayoutConfig: Codable {
    public var gaps: CGFloat = 16
    public var outerGaps: EdgeInsets = EdgeInsets(top: 0, bottom: 0, left: 0, right: 0)
    public var centerFocusedColumn: CenterMode = .never
    public var presetWidths: [ColumnWidth] = ColumnWidth.presets
    public var defaultWidth: ColumnWidth = .proportion(0.5)

    public struct EdgeInsets: Codable {
        public var top: CGFloat
        public var bottom: CGFloat
        public var left: CGFloat
        public var right: CGFloat

        public init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
            self.top = top
            self.bottom = bottom
            self.left = left
            self.right = right
        }
    }

    public enum CenterMode: String, Codable {
        case never
        case always
        case onOverflow = "on-overflow"
    }

    public init() {}
}

public struct AnimationConfig: Codable {
    public var enabled: Bool = true
    public var workspaceSwitch: SpringConfig = .default
    public var horizontalMovement: SpringConfig = .snappy
    public var windowResize: SpringConfig = .default

    public init() {}
}

public struct InputConfig: Codable {
    public var scrollThreshold: CGFloat = Constants.scrollThreshold
    public var scrollMultiplier: CGFloat = Constants.scrollMultiplier
    public var triggerCooldown: TimeInterval = Constants.triggerCooldown

    public init() {}
}

public struct NiriConfig: Codable {
    public var layout: LayoutConfig = LayoutConfig()
    public var animation: AnimationConfig = AnimationConfig()
    public var input: InputConfig = InputConfig()
    public var windowRules: [WindowRule] = []

    public init() {}
}

public struct WindowRule: Codable {
    public enum Matcher: Codable {
        case appID(String)
        case titleContains(String)
        case titleRegex(String)

        private enum CodingKeys: String, CodingKey {
            case type, value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let value = try container.decode(String.self, forKey: .value)
            switch type {
            case "app-id": self = .appID(value)
            case "title-contains": self = .titleContains(value)
            case "title-regex": self = .titleRegex(value)
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Matcher type: \(type)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .appID(let v):
                try container.encode("app-id", forKey: .type)
                try container.encode(v, forKey: .value)
            case .titleContains(let v):
                try container.encode("title-contains", forKey: .type)
                try container.encode(v, forKey: .value)
            case .titleRegex(let v):
                try container.encode("title-regex", forKey: .type)
                try container.encode(v, forKey: .value)
            }
        }
    }

    public enum Action: Codable {
        case float
        case fixedWidth(CGFloat)
        case workspace(Int)

        private enum CodingKeys: String, CodingKey {
            case type, value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "float": self = .float
            case "fixed-width":
                let value = try container.decode(CGFloat.self, forKey: .value)
                self = .fixedWidth(value)
            case "workspace":
                let value = try container.decode(Int.self, forKey: .value)
                self = .workspace(value)
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Action type: \(type)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .float:
                try container.encode("float", forKey: .type)
            case .fixedWidth(let v):
                try container.encode("fixed-width", forKey: .type)
                try container.encode(v, forKey: .value)
            case .workspace(let v):
                try container.encode("workspace", forKey: .type)
                try container.encode(v, forKey: .value)
            }
        }
    }

    public var matchers: [Matcher]
    public var actions: [Action]
}
