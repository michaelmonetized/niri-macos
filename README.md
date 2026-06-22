# niri-macos

A native macOS implementation of [niri](https://github.com/YaLTeR/niri)'s scrollable-tiling window management paradigm.

<p align="center">
  <strong>🪟 Infinite horizontal workspace • 📜 Smooth scrolling • ✨ Native Swift</strong>
</p>

## What is this?

niri is a revolutionary Wayland compositor that reimagines tiling window management. Instead of rigid grids, windows are arranged in columns on an **infinite horizontal strip**. You scroll through your windows like a document.

**niri-macos** brings this paradigm to macOS using native Accessibility APIs.

## Key Concepts

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Infinite Workspace                              │
│                                                                             │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │      │ │      │ │      │ │██████│ │      │ │      │ │      │           │
│  │ Win1 │ │ Win2 │ │ Win3 │ │Win4██│ │ Win5 │ │ Win6 │ │ Win7 │  ...      │
│  │      │ │      │ │      │ │██████│ │      │ │      │ │      │           │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘           │
│           ◄────────── visible ──────────►                                   │
│                     (screen viewport)                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                        ◄── scroll ──►
```

**Core principles:**
- **Opening a window never resizes existing windows** - new windows appear at the end
- **Every monitor has its own workspace** - windows can't "overflow" to adjacent monitors
- **Workspaces are dynamic** - vertical workspaces appear/disappear as needed
- **Smooth gestures** - trackpad swipe to scroll through windows

## Why not PaperWM.spoon?

[PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) is excellent, but:

| Feature | PaperWM.spoon | niri-macos |
|---------|--------------|------------|
| Runtime | Hammerspoon (Lua) | Native Swift |
| Performance | Good | Better (direct API access) |
| Window hints | Polling | Event-driven |
| Animations | Basic | Spring physics |
| IPC | None | JSON socket (like yabai) |
| Gestures | Trackpad only | Trackpad + mouse |
| Integration | Standalone | Works with skhd/sketchybar |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        niri-macos daemon                         │
├──────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │   Workspace    │  │    Layout      │  │    Animation       │ │
│  │   Manager      │  │    Engine      │  │    Controller      │ │
│  │                │  │                │  │                    │ │
│  │ • Per-monitor  │  │ • Column grid  │  │ • Spring physics   │ │
│  │ • Dynamic      │  │ • Scroll state │  │ • Gesture interp   │ │
│  │ • Persistence  │  │ • Focus logic  │  │ • 60fps updates    │ │
│  └───────┬────────┘  └───────┬────────┘  └─────────┬──────────┘ │
│          │                   │                     │            │
│          └───────────────────┼─────────────────────┘            │
│                              ▼                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Window Controller                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │ │
│  │  │ AX Observer  │  │ SkyLight API │  │ CGWindow API     │  │ │
│  │  │ (events)     │  │ (positions)  │  │ (info/capture)   │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌────────────────┐  ┌───────┴───────┐  ┌────────────────────┐ │
│  │ IPC Server     │  │ Gesture Input │  │ Config Manager     │ │
│  │ (Unix socket)  │  │ (CGEvent tap) │  │ (JSON)             │ │
│  └────────────────┘  └───────────────┘  └────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
    ┌──────────┐        ┌───────────┐        ┌────────────┐
    │ niri-msg │        │   skhd    │        │ sketchybar │
    │ (CLI)    │        │ (hotkeys) │        │ (status)   │
    └──────────┘        └───────────┘        └────────────┘
```

## Installation

```bash
# Build from source
git clone https://github.com/yourusername/niri-macos
cd niri-macos
swift build -c release

# Install
cp .build/release/niri-macos ~/.local/bin/

# Grant accessibility permissions
# System Preferences → Privacy & Security → Accessibility → niri-macos ✓
```

## Usage

```bash
# Start the daemon
niri-macos

# With options
niri-macos --config ~/.config/niri-macos/config.json
niri-macos --socket /tmp/custom.sock
niri-macos --log-level debug

# Send commands via IPC
niri-msg focus-column-left
niri-msg focus-column-right
niri-msg move-column-left
niri-msg center-column

# niri-msg with custom socket
niri-msg --socket /tmp/custom.sock status
```

### CLI Options

| Flag | Description | Default |
|------|-------------|---------|
| `-c, --config <path>` | Config file path | `~/.config/niri-macos/config.json` |
| `-s, --socket <path>` | IPC socket path | `/tmp/niri-macos.sock` |
| `--log-level <level>` | debug, info, error | info |
| `-v, --version` | Show version | |
| `-h, --help` | Show help | |

## Configuration

Config file: `~/.config/niri-macos/config.json`

```json
{
  "layout": {
    "gaps": 16,
    "outerGaps": { "top": 0, "bottom": 0, "left": 0, "right": 0 },
    "centerFocusedColumn": "never",
    "presetWidths": [
      { "type": "proportion", "value": 0.33 },
      { "type": "proportion", "value": 0.5 },
      { "type": "proportion", "value": 0.66 },
      { "type": "proportion", "value": 1.0 }
    ],
    "defaultWidth": { "type": "proportion", "value": 0.5 }
  },
  "animation": {
    "enabled": true,
    "workspaceSwitch": { "damping": 0.8, "stiffness": 500, "mass": 1.0, "epsilon": 0.001 },
    "horizontalMovement": { "damping": 0.9, "stiffness": 800, "mass": 1.0, "epsilon": 0.001 },
    "windowResize": { "damping": 0.8, "stiffness": 500, "mass": 1.0, "epsilon": 0.001 }
  },
  "input": {
    "scrollThreshold": 25,
    "scrollMultiplier": 1.5,
    "triggerCooldown": 0.15
  },
  "windowRules": [
    {
      "matchers": [{ "type": "app-id", "value": "com.apple.systempreferences" }],
      "actions": [{ "type": "float" }]
    }
  ]
}
```

`centerFocusedColumn` options: `"never"`, `"always"`, `"on-overflow"`

## Gestures & Scroll Controls

### Mouse/Trackpad Scroll Gestures

| Gesture | Action |
|---------|--------|
| **Cmd+Shift+scroll** | Focus previous/next window (1 scroll = 1 window) |
| **Cmd+scroll** | Switch workspace up/down (1 scroll = 1 workspace) |
| **3-finger swipe** | Free scroll through windows |

### Scroll Behavior

The scroll gestures use **discrete snapping**:
- One scroll "click" moves focus to exactly one window/workspace
- No gradual scrolling or momentum for modifier-based scrolling
- Smooth free-scroll available with 3-finger swipe (no modifiers)

## skhd Integration

```bash
# ~/.config/skhd/skhdrc

# Focus
alt - h : niri-msg focus-column-left
alt - l : niri-msg focus-column-right  
alt - j : niri-msg focus-window-down
alt - k : niri-msg focus-window-up

# Move columns
alt + shift - h : niri-msg move-column-left
alt + shift - l : niri-msg move-column-right

# Move windows within column
alt + shift - j : niri-msg move-window-down
alt + shift - k : niri-msg move-window-up

# Sizing
alt - w : niri-msg switch-preset-column-width
alt - f : niri-msg toggle-fullscreen
alt - c : niri-msg center-column
alt - m : niri-msg maximize-column

# Consume/expel (column stacking)
ctrl + alt - h : niri-msg consume-window-into-column
ctrl + alt - l : niri-msg expel-window-from-column

# Workspaces
alt - 1 : niri-msg focus-workspace 1
alt - 2 : niri-msg focus-workspace 2
alt - 3 : niri-msg focus-workspace 3
alt + shift - 1 : niri-msg move-window-to-workspace 1
alt + shift - 2 : niri-msg move-window-to-workspace 2
alt + shift - 3 : niri-msg move-window-to-workspace 3
alt - u : niri-msg workspace-up
alt - d : niri-msg workspace-down

# Create workspace above/below current (Meh key = Ctrl+Option+Shift)
ctrl + alt + shift - k : niri-msg create-workspace-above
ctrl + alt + shift - j : niri-msg create-workspace-below
ctrl + alt + shift - up : niri-msg create-workspace-above
ctrl + alt + shift - down : niri-msg create-workspace-below

# Split groups (for centered multi-window layouts)
ctrl + alt - s : niri-msg create-split-horizontal
ctrl + alt - v : niri-msg create-split-vertical
ctrl + alt - q : niri-msg create-split-quad

# Scroll (if not using trackpad gestures)
alt + ctrl - h : niri-msg scroll-workspace -200
alt + ctrl - l : niri-msg scroll-workspace 200

# Debug
alt + shift - s : niri-msg status
alt + shift - w : niri-msg list-windows
```

## IPC Commands

### Navigation
```bash
niri-msg focus-column-left          # Move focus to the left column
niri-msg focus-column-right         # Move focus to the right column
niri-msg focus-column-first         # Move focus to the first column
niri-msg focus-column-last          # Move focus to the last column
niri-msg focus-window-up            # Move focus up within column
niri-msg focus-window-down          # Move focus down within column
```

### Movement
```bash
niri-msg move-column-left           # Move focused column left
niri-msg move-column-right          # Move focused column right
niri-msg move-window-up             # Move focused window up in column
niri-msg move-window-down           # Move focused window down in column
```

### Column Operations
```bash
niri-msg consume-window-into-column # Merge next window into current column
niri-msg expel-window-from-column   # Split focused window to new column
```

### Sizing
```bash
niri-msg switch-preset-column-width # Cycle through widths (33%, 50%, 66%, 100%)
niri-msg set-column-width 50%       # Set column to 50% width
niri-msg set-column-width +10%      # Increase width by 10%
niri-msg set-column-width -50       # Decrease width by 50 pixels
niri-msg set-column-width 800       # Set width to 800 pixels
niri-msg center-column              # Center the focused column on screen
niri-msg maximize-column            # Maximize column to full width
niri-msg toggle-fullscreen          # Toggle between maximized and default
```

### Scrolling
```bash
niri-msg scroll-workspace -200      # Scroll left by 200 pixels
niri-msg scroll-workspace 200       # Scroll right by 200 pixels
```

### Workspaces
```bash
niri-msg focus-workspace 1          # Switch to workspace 1
niri-msg focus-workspace 2          # Switch to workspace 2
niri-msg move-window-to-workspace 2 # Move focused window to workspace 2
niri-msg workspace-up               # Switch to previous workspace
niri-msg workspace-down             # Switch to next workspace (creates if needed)
niri-msg create-workspace-above     # Create new workspace above current and switch to it
niri-msg create-workspace-below     # Create new workspace below current and switch to it
```

### Split Groups
```bash
niri-msg create-split-horizontal    # Create 2-window side-by-side layout (50/50)
niri-msg create-split-vertical      # Create 2-window stacked layout (50/50)
niri-msg create-split-quad          # Create 4-window 2x2 grid layout (25% each)
```

Split groups take windows from the focused column (and adjacent columns if needed) 
and arrange them in a centered, balanced layout filling the screen.

### Debug
```bash
niri-msg list-windows               # List all managed windows
niri-msg status                     # Show current layout status
```

### Control
```bash
niri-msg quit                       # Quit niri-macos daemon
```

## Current Status

**Working**

- [x] Project structure (NiriCore library + executables)
- [x] Window enumeration (CGWindowList + Accessibility APIs)
- [x] AXWindowObserver (event-driven window tracking)
- [x] Horizontal layout engine (scrollable columns)
- [x] Scroll state management + animated scrolling
- [x] Gesture recognition (trackpad swipe, modifier+scroll)
- [x] Animation system (spring physics, CVDisplayLink 60fps)
- [x] IPC server (Unix socket, JSON protocol)
- [x] Complete niri-msg CLI
- [x] Configuration system (JSON)
- [x] Multi-monitor support (per-monitor isolation)
- [x] Workspace operations (up/down/create above/below)
- [x] Split group layouts (horizontal/vertical/quad)
- [x] Test suite (112 tests)
- [x] CI (GitHub Actions)

**Planned**

- [ ] Focus ring overlay
- [ ] Window rule enforcement (float, fixed width, workspace assignment)
- [ ] Overview mode
- [ ] Sketchybar integration
- [ ] Homebrew formula

### Permissions Required

**Accessibility** - Required for window management and gesture recognition.
Grant in: System Settings → Privacy & Security → Accessibility → niri-macos ✓

## Inspiration & Credits

- [niri](https://github.com/YaLTeR/niri) - The original scrollable-tiling compositor
- [yabai](https://github.com/koekeishiya/yabai) - macOS tiling WM (SkyLight API reference)
- [PaperWM](https://github.com/paperwm/PaperWM) - GNOME extension that started it all
- [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) - Hammerspoon implementation

## License

MIT
