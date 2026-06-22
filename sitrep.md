# niri-macos

**One-liner:** macOS port of niri scrollable tiling Wayland compositor concepts.

## Status: **FUNCTIONAL**

- **Last Updated:** 2026-02-09
- **Tech Stack:** Swift, SPM, Accessibility APIs, CGWindowList, CVDisplayLink
- **Tests:** 112 passing
- **CI:** GitHub Actions (build + test + release build)

## What's Working
- Full scrollable-tiling layout engine (columns on infinite horizontal strip)
- Spring-physics animation system at 60fps (CVDisplayLink)
- Event-driven window tracking via AXObserver
- Multi-monitor support with per-monitor workspace isolation
- Dynamic workspaces (create above/below, switch up/down)
- Split group layouts (horizontal, vertical, quad)
- IPC server (Unix domain socket, JSON protocol)
- niri-msg CLI for all commands
- JSON configuration system (`~/.config/niri-macos/config.json`)
- Trackpad gesture recognition (3-finger swipe, Cmd+scroll, Cmd+Shift+scroll)
- Menubar app with all operations accessible

## Architecture
- `NiriCore` library target (all logic, testable)
- `niri-macos` executable (thin AppDelegate shell)
- `niri-msg` executable (IPC client CLI)
- Protocol-based DI (WindowManipulating, WindowEnumerating, Logging)
- Thread safety: main-thread serialization for layout, NSLock for logger

## Next Steps
1. Focus ring overlay (visual indicator for focused column)
2. Window rule enforcement (currently parsed but not applied)
3. Sketchybar integration for workspace status
4. Homebrew formula
