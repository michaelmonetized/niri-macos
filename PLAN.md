# niri-macos Implementation Plan

## Phase 0: Foundation ✅
**Goal:** Project setup and basic structure

- [x] Project structure (Package.swift)
- [x] Basic menubar app
- [x] Logging infrastructure
- [ ] Proper daemon mode (launchd plist)

---

## Phase 1: Window Observation
**Goal:** Track all windows and their state changes

### 1.1 Window Enumeration
- [ ] Use CGWindowListCopyWindowInfo for window list
- [ ] Filter to standard windows (no menus, tooltips)
- [ ] Track window ID, app, title, frame, space

### 1.2 Accessibility Observer
- [ ] Create AXObserver for each running app
- [ ] Subscribe to: created, destroyed, moved, resized, focused
- [ ] Map AXUIElement ↔ CGWindowID

### 1.3 Space Detection
- [ ] Use CGSCopyManagedDisplaySpaces (private API)
- [ ] Track which windows are on which space
- [ ] Detect space switches

### 1.4 Window Model
```swift
struct ManagedWindow {
    let id: CGWindowID
    let axElement: AXUIElement
    let appPID: pid_t
    let bundleId: String
    var frame: CGRect
    var space: Int
    var isMinimized: Bool
    var isFloating: Bool
}
```

**Deliverable:** Can log all window changes in real-time

---

## Phase 2: Layout Engine
**Goal:** Implement niri's scrolling layout model

### 2.1 Data Structures
```swift
struct Column {
    var windows: [ManagedWindow]
    var width: ColumnWidth
    var x: CGFloat  // Position in infinite strip
}

enum ColumnWidth {
    case proportion(CGFloat)  // 0.33, 0.5, 0.66, 1.0
    case fixed(CGFloat)       // Pixels
}

struct Workspace {
    var columns: [Column]
    var scrollOffset: CGFloat  // View position in strip
    var focusedColumn: Int
    var focusedWindow: Int     // Index within column
}

struct Monitor {
    let screen: NSScreen
    var workspaces: [Workspace]
    var activeWorkspace: Int
}
```

### 2.2 Layout Calculation
- [ ] Calculate visible columns based on scrollOffset
- [ ] Determine target frames for each window
- [ ] Handle gaps and margins
- [ ] Implement focus-follows-scroll

### 2.3 Focus Management
- [ ] Track focused column and window
- [ ] Implement focus-column-left/right
- [ ] Implement focus-window-up/down
- [ ] Auto-scroll to keep focus visible

### 2.4 Layout Operations
- [ ] Insert window (always at end, or after focus)
- [ ] Remove window (close gap)
- [ ] Move column left/right
- [ ] Move window up/down within column
- [ ] Consume window into column (stacking)
- [ ] Expel window from column

**Deliverable:** Layout engine calculates correct positions

---

## Phase 3: Window Control
**Goal:** Actually move and resize windows

### 3.1 AXUIElement Manipulation
- [ ] Set AXPosition attribute
- [ ] Set AXSize attribute
- [ ] Handle windows that resist sizing
- [ ] Batch updates for performance

### 3.2 Animation System
```swift
struct SpringAnimation {
    var damping: CGFloat
    var stiffness: CGFloat
    var velocity: CGFloat
    var target: CGFloat
    var current: CGFloat
    
    mutating func step(dt: TimeInterval) -> CGFloat
}

class AnimationController {
    var animations: [CGWindowID: WindowAnimation]
    var displayLink: CVDisplayLink
    
    func animate(window: CGWindowID, to frame: CGRect)
    func tick()  // Called at 60fps
}
```

### 3.3 Smooth Scrolling
- [ ] Animate scrollOffset changes
- [ ] Spring physics for natural feel
- [ ] Momentum for swipe gestures

**Deliverable:** Windows animate smoothly to positions

---

## Phase 4: Input Handling
**Goal:** Respond to gestures and commands

### 4.1 Gesture Recognition
- [ ] CGEventTap for trackpad events
- [ ] Detect 3-finger horizontal swipe
- [ ] Convert swipe delta to scroll offset
- [ ] Momentum physics after release

### 4.2 Keyboard Shortcuts (via skhd)
- [ ] No built-in hotkeys (use skhd)
- [ ] Document recommended bindings

### 4.3 Mouse Handling
- [ ] Modifier+scroll to scroll workspace
- [ ] Modifier+drag to rearrange columns

**Deliverable:** Can scroll with trackpad gestures

---

## Phase 5: IPC Server
**Goal:** External control via socket

### 5.1 Socket Server
- [ ] Unix domain socket at /tmp/niri-macos.sock
- [ ] JSON message protocol
- [ ] Request/response pattern

### 5.2 Command Protocol
```json
// Request
{"command": "focus-column-left"}
{"command": "set-column-width", "args": {"width": "+10%"}}

// Response  
{"success": true}
{"success": false, "error": "No window focused"}
```

### 5.3 CLI Tool (niri-msg)
- [ ] Simple Swift CLI
- [ ] Connects to socket, sends command, prints result

### 5.4 Event Subscription
- [ ] Clients can subscribe to events
- [ ] Window focused, workspace changed, etc.
- [ ] For sketchybar integration

**Deliverable:** Can control via `niri-msg` commands

---

## Phase 6: Configuration
**Goal:** User-configurable behavior

### 6.1 Config Format
- [ ] KDL format (like niri)
- [ ] Or TOML for simplicity
- [ ] Live reload on file change

### 6.2 Config Options
```kdl
layout {
    gaps 16
    center-focused-column "on-overflow"
    preset-column-widths { 0.33; 0.5; 0.66; 1.0 }
    default-column-width 0.5
}

animations {
    enabled true
    spring { damping 0.8; stiffness 500 }
}

window-rules {
    match app-id="com.apple.finder" { floating true }
}
```

### 6.3 Window Rules
- [ ] Match by app-id, title regex
- [ ] Actions: float, fixed-size, workspace assignment

**Deliverable:** Customizable via config file

---

## Phase 7: Visual Feedback
**Goal:** Show focus and state

### 7.1 Focus Ring
- [ ] Overlay window around focused window
- [ ] Colored border (configurable)
- [ ] Animates with window

### 7.2 Overview Mode
- [ ] Zoom out to see all columns
- [ ] Click to focus
- [ ] Like niri's overview

### 7.3 Status Integration
- [ ] Export state for sketchybar
- [ ] Current workspace, window count, etc.

**Deliverable:** Visual indicators for state

---

## Phase 8: Polish
**Goal:** Production-ready

### 8.1 Robustness
- [ ] Handle app crashes gracefully
- [ ] Recover from layout corruption
- [ ] Memory management

### 8.2 Performance
- [ ] Profile and optimize
- [ ] Minimize API calls
- [ ] Efficient animation loop

### 8.3 Distribution
- [ ] Homebrew formula
- [ ] Signed binary
- [ ] Documentation site

---

## Technical Challenges

### Private APIs
macOS window management requires private APIs:
- `SkyLight.framework` - Window positioning
- `CGSSpace*` - Space management
- Some may break between macOS versions

**Mitigation:** Abstract behind protocol, version-specific implementations

### Accessibility Permissions
Requires user to grant accessibility access:
- First launch prompts
- Need to guide user through settings

### Window Resistance
Some apps resist resizing:
- Electron apps have minimum sizes
- Terminal apps snap to character grid

**Mitigation:** Track actual size after resize, adjust layout

### Animation Conflicts
Multiple systems trying to move windows:
- Mission Control
- Stage Manager
- Full-screen transitions

**Mitigation:** Detect system animations, pause layout

---

## Milestones

| Milestone | Phases | Target |
|-----------|--------|--------|
| MVP | 1-3 | Manual window arrangement works |
| Usable | 4-5 | Gestures and IPC work |
| Complete | 6-8 | Full feature parity |

---

## Resources

- [yabai source](https://github.com/koekeishiya/yabai) - SkyLight API usage
- [niri source](https://github.com/YaLTeR/niri) - Layout algorithms
- [AXUIElement docs](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [CGWindow docs](https://developer.apple.com/documentation/coregraphics/quartz_window_services)
