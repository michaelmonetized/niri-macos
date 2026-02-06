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
│  │ (Unix socket)  │  │ (CGEvent tap) │  │ (live reload)      │ │
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

# With a config file
niri-macos --config ~/.config/niri-macos/config.kdl

# Send commands via IPC
niri-msg focus-column-left
niri-msg focus-column-right
niri-msg move-column-left
niri-msg center-column
```

## Configuration

```kdl
// ~/.config/niri-macos/config.kdl

layout {
    gaps 16
    center-focused-column "never"  // "never" | "always" | "on-overflow"
    
    preset-column-widths {
        proportion 0.33
        proportion 0.5  
        proportion 0.66
    }
    
    default-column-width { proportion 0.5; }
    
    focus-ring {
        width 2
        color "#7aa2f7"
    }
}

animations {
    workspace-switch {
        spring damping-ratio=0.8 stiffness=500 epsilon=0.001
    }
    horizontal-view-movement {
        spring damping-ratio=0.9 stiffness=800 epsilon=0.001
    }
    window-resize {
        spring damping-ratio=0.8 stiffness=500 epsilon=0.001
    }
}

input {
    trackpad {
        scroll-factor 0.5
        natural-scroll true
    }
}

window-rules {
    // Float certain windows
    match app-id="com.apple.systempreferences" {
        floating true
    }
    match title~"^Preferences$" {
        floating true
    }
}
```

## skhd Integration

```bash
# ~/.config/skhd/skhdrc

# Focus
alt - h : niri-msg focus-column-left
alt - l : niri-msg focus-column-right  
alt - j : niri-msg focus-window-down
alt - k : niri-msg focus-window-up

# Move
alt + shift - h : niri-msg move-column-left
alt + shift - l : niri-msg move-column-right
alt + shift - j : niri-msg move-window-down
alt + shift - k : niri-msg move-window-up

# Sizing
alt - r : niri-msg switch-preset-column-width
alt - f : niri-msg maximize-column
alt - c : niri-msg center-column

# Workspaces (vertical)
alt - 1 : niri-msg focus-workspace 1
alt - 2 : niri-msg focus-workspace 2
alt + shift - 1 : niri-msg move-window-to-workspace 1
alt + shift - 2 : niri-msg move-window-to-workspace 2

# Consume/expel (column stacking)
alt - i : niri-msg consume-window-into-column
alt - o : niri-msg expel-window-from-column
```

## IPC Commands

```bash
niri-msg focus-column-left
niri-msg focus-column-right
niri-msg focus-column-first
niri-msg focus-column-last
niri-msg focus-window-up
niri-msg focus-window-down

niri-msg move-column-left
niri-msg move-column-right
niri-msg move-window-up
niri-msg move-window-down

niri-msg consume-window-into-column
niri-msg expel-window-from-column

niri-msg center-column
niri-msg maximize-column
niri-msg switch-preset-column-width
niri-msg set-column-width [+|-]<pixels|%>

niri-msg focus-workspace <index>
niri-msg move-window-to-workspace <index>

niri-msg spawn <command>
niri-msg quit
```

## Current Status

🚧 **Early Development** 🚧

- [x] Project structure
- [x] Basic window enumeration
- [ ] Accessibility API integration
- [ ] Horizontal layout engine
- [ ] Scroll state management
- [ ] Gesture recognition
- [ ] Animation system
- [ ] IPC server
- [ ] Configuration system
- [ ] Focus ring overlay

## Inspiration & Credits

- [niri](https://github.com/YaLTeR/niri) - The original scrollable-tiling compositor
- [yabai](https://github.com/koekeishiya/yabai) - macOS tiling WM (SkyLight API reference)
- [PaperWM](https://github.com/paperwm/PaperWM) - GNOME extension that started it all
- [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) - Hammerspoon implementation

## License

MIT
