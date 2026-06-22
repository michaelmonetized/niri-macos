# niri-macos Hotkeys & Gestures

Complete reference for all input controls.

## Trackpad/Mouse Gestures

| Gesture | Action | Notes |
|---------|--------|-------|
| **Cmd+Shift+scroll** | Focus previous/next window | 1 scroll click = 1 window change |
| **Cmd+scroll (vertical)** | Switch workspace up/down | 1 scroll click = 1 workspace |
| **3-finger horizontal swipe** | Free scroll through windows | Continuous with momentum |

### Scroll Behavior

- **Discrete mode (default)**: Modifier+scroll snaps to next/previous item
- **Continuous mode**: 3-finger swipe for free scrolling with momentum
- Each scroll "click" on trackpad = exactly one window or workspace switch

## Keyboard Shortcuts (skhd)

### Navigation

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Alt+H` | `focus-column-left` | Focus window to the left |
| `Alt+L` | `focus-column-right` | Focus window to the right |
| `Alt+J` | `focus-window-down` | Focus window below (in same column) |
| `Alt+K` | `focus-window-up` | Focus window above (in same column) |

### Move Windows

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Alt+Shift+H` | `move-column-left` | Move column left |
| `Alt+Shift+L` | `move-column-right` | Move column right |
| `Alt+Shift+J` | `move-window-down` | Move window down in column |
| `Alt+Shift+K` | `move-window-up` | Move window up in column |

### Sizing

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Alt+W` | `switch-preset-column-width` | Cycle widths (33%, 50%, 66%, 100%) |
| `Alt+F` | `toggle-fullscreen` | Toggle fullscreen/default width |
| `Alt+C` | `center-column` | Center focused column on screen |
| `Alt+M` | `maximize-column` | Maximize column width |

### Column Stacking

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Ctrl+Alt+H` | `consume-window-into-column` | Add next window to current column |
| `Ctrl+Alt+L` | `expel-window-from-column` | Split focused window to new column |

### Workspaces

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Alt+1` | `focus-workspace 1` | Switch to workspace 1 |
| `Alt+2` | `focus-workspace 2` | Switch to workspace 2 |
| `Alt+3` | `focus-workspace 3` | Switch to workspace 3 |
| `Alt+Shift+1` | `move-window-to-workspace 1` | Move window to workspace 1 |
| `Alt+Shift+2` | `move-window-to-workspace 2` | Move window to workspace 2 |
| `Alt+U` | `workspace-up` | Switch to previous workspace |
| `Alt+D` | `workspace-down` | Switch to next workspace |

### Workspace Creation (Meh Key / Hyper Key)

**Meh key** = `Ctrl+Option+Shift` (3 modifiers)
**Hyper key** = `Ctrl+Option+Cmd+Shift` (4 modifiers)

Both work for workspace creation:

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Meh+K` / `Hyper+K` | `create-workspace-above` | Create workspace above current |
| `Meh+J` / `Hyper+J` | `create-workspace-below` | Create workspace below current |
| `Meh+Up` / `Hyper+Up` | `create-workspace-above` | Create workspace above current |
| `Meh+Down` / `Hyper+Down` | `create-workspace-below` | Create workspace below current |

### Split Groups

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Ctrl+Alt+S` | `create-split-horizontal` | 2 windows side-by-side (50/50) |
| `Ctrl+Alt+V` | `create-split-vertical` | 2 windows stacked (50/50) |
| `Ctrl+Alt+Q` | `create-split-quad` | 4 windows in 2x2 grid |

### Debug

| Shortcut | Command | Description |
|----------|---------|-------------|
| `Alt+Shift+S` | `status` | Show current layout status |
| `Alt+Shift+W` | `list-windows` | List all managed windows |

## Multi-Monitor Behavior

- **Each monitor has isolated workspaces** - windows don't bleed to adjacent displays
- **Mouse position determines active monitor** - commands affect the monitor under cursor
- Scroll gestures work on whichever monitor the cursor is on

## Complete skhd Config

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

# Consume/expel
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

# Create workspaces (Meh key = Ctrl+Alt+Shift)
ctrl + alt + shift - k : niri-msg create-workspace-above
ctrl + alt + shift - j : niri-msg create-workspace-below
ctrl + alt + shift - up : niri-msg create-workspace-above
ctrl + alt + shift - down : niri-msg create-workspace-below

# Create workspaces (Hyper key = Ctrl+Alt+Cmd+Shift = MEH + Cmd)
ctrl + alt + cmd + shift - k : niri-msg create-workspace-above
ctrl + alt + cmd + shift - j : niri-msg create-workspace-below
ctrl + alt + cmd + shift - up : niri-msg create-workspace-above
ctrl + alt + cmd + shift - down : niri-msg create-workspace-below

# Split groups
ctrl + alt - s : niri-msg create-split-horizontal
ctrl + alt - v : niri-msg create-split-vertical
ctrl + alt - q : niri-msg create-split-quad

# Debug
alt + shift - s : niri-msg status
alt + shift - w : niri-msg list-windows
```
