# niri-macos Implementation Plan

## Phase 0: Foundation ✅
**Goal:** Project setup and basic structure

- [x] Project structure (Package.swift)
- [x] Basic menubar app
- [x] Logging infrastructure
- [ ] Proper daemon mode (launchd plist)

---

## Phase 1: Window Observation ✅
**Goal:** Track all windows and their state changes

### 1.1 Window Enumeration ✅
- [x] Use CGWindowListCopyWindowInfo for window list
- [x] Filter to standard windows (no menus, tooltips)
- [x] Track window ID, app, title, frame, space

### 1.2 Accessibility Observer ✅
- [x] Create AXObserver for each running app
- [x] Subscribe to: created, destroyed, moved, resized, focused
- [x] Map AXUIElement ↔ CGWindowID

### 1.3 Space Detection
- [ ] Use CGSCopyManagedDisplaySpaces (private API)
- [ ] Track which windows are on which space
- [ ] Detect space switches

### 1.4 Window Model ✅
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

**Deliverable:** Can log all window changes in real-time ✅

---

## Phase 2: Layout Engine ✅
**Goal:** Implement niri's scrolling layout model

### 2.1 Data Structures ✅
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

### 2.2 Layout Calculation ✅
- [x] Calculate visible columns based on scrollOffset
- [x] Determine target frames for each window
- [x] Handle gaps and margins
- [x] Implement focus-follows-scroll

### 2.3 Focus Management ✅
- [x] Track focused column and window
- [x] Implement focus-column-left/right
- [x] Implement focus-window-up/down
- [x] Auto-scroll to keep focus visible

### 2.4 Layout Operations ✅
- [x] Insert window (always at end, or after focus)
- [x] Remove window (close gap)
- [x] Move column left/right
- [x] Move window up/down within column
- [x] Consume window into column (stacking)
- [x] Expel window from column

**Deliverable:** Layout engine calculates correct positions ✅

---

## Phase 3: Window Control ✅
**Goal:** Actually move and resize windows

### 3.1 AXUIElement Manipulation ✅
- [x] Set AXPosition attribute
- [x] Set AXSize attribute
- [x] Handle windows that resist sizing
- [x] Batch updates for performance

### 3.2 Animation System ✅
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

### 3.3 Smooth Scrolling ✅
- [x] Animate scrollOffset changes
- [x] Spring physics for natural feel
- [x] Momentum for swipe gestures

**Deliverable:** Windows animate smoothly to positions ✅

---

## Phase 4: Input Handling ✅
**Goal:** Respond to gestures and commands

### 4.1 Gesture Recognition ✅
- [x] CGEventTap for trackpad events
- [x] Detect horizontal swipe
- [x] Convert swipe delta to scroll offset
- [x] Momentum physics after release

### 4.2 Keyboard Shortcuts (via skhd) ✅
- [x] No built-in hotkeys (use skhd)
- [x] Document recommended bindings

### 4.3 Mouse Handling
- [x] Modifier+scroll to scroll workspace
- [ ] Modifier+drag to rearrange columns

**Deliverable:** Can scroll with trackpad gestures ✅

---

## Phase 5: IPC Server ✅
**Goal:** External control via socket

### 5.1 Socket Server ✅
- [x] Unix domain socket at /tmp/niri-macos.sock
- [x] JSON message protocol
- [x] Request/response pattern

### 5.2 Command Protocol ✅
```json
// Request
{"command": "focus-column-left"}
{"command": "set-column-width", "args": {"width": "+10%"}}

// Response  
{"success": true}
{"success": false, "error": "No window focused"}
```

### 5.3 CLI Tool (niri-msg) ✅
- [x] Simple Swift CLI
- [x] Connects to socket, sends command, prints result
- [x] Complete command set: focus, move, consume/expel, size, scroll, workspace

### 5.4 Event Subscription
- [ ] Clients can subscribe to events
- [ ] Window focused, workspace changed, etc.
- [ ] For sketchybar integration

**Deliverable:** Can control via `niri-msg` commands ✅

---

## Phase 6: Configuration ✅ (JSON at HEAD)
**Goal:** User-configurable behavior

### 6.1 Config Format
- [x] **JSON** config at `~/.config/niri-macos/config.json` (`ConfigManager.swift`)
- [x] Codable decode path + tests (`ConfigCodableTests`)
- [ ] Live reload on file change
- [ ] ~~KDL format (like upstream niri)~~ **Not shipped** — HEAD parser is JSON, not KDL. KDL remains a possible future, not current.

### 6.2 Config Options
Shipped shape is JSON (illustrative):
```json
{
  "layout": {
    "gaps": 16,
    "defaultColumnWidth": 0.5
  },
  "animations": {
    "enabled": true
  },
  "windowRules": [
    { "appId": "com.apple.finder", "floating": true }
  ]
}
```

### 6.3 Window Rules
- [x] Parsed / Codable window-rule path exists
- [ ] Enforcement applied to live layout (sitrep: parsed but not fully applied)

**Deliverable:** Customizable via JSON config file ✅ (enforcement of rules still open)

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

| Milestone | Phases | Status |
|-----------|--------|--------|
| MVP | 1-3 | ✅ Complete |
| Usable | 4-5 | ✅ Complete |
| Complete | 6-8 | 🚧 In progress |

---

## Resources

- [yabai source](https://github.com/koekeishiya/yabai) - SkyLight API usage
- [niri source](https://github.com/YaLTeR/niri) - Layout algorithms
- [AXUIElement docs](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [CGWindow docs](https://developer.apple.com/documentation/coregraphics/quartz_window_services)


*PLAN parity sync: 2026-09-08 — Phase 6 aligned to JSON HEAD.*
