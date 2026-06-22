# AUTOPSY.md

## niri-macos: Post-Mortem of a Codebase That Technically Runs

**Date of examination:** 2026-02-09
**Cause of death:** Still alive, but on life support. The patient is a 3,672-line Swift prototype that manages your windows with the structural integrity of a Jenga tower on a washing machine.

---

## Executive Summary

niri-macos is what happens when someone looks at a Wayland compositor written in Rust with years of engineering behind it and says "I'll just rewrite this in Swift over a weekend using the Accessibility API." It's the software equivalent of recreating the Mona Lisa on a napkin at Denny's.

Against all odds, it kind of works.

---

## The Numbers Don't Lie (But They Do Wince)

| Metric | Value | Reaction |
|--------|-------|----------|
| Total commits | **2** | Two. The entire project history fits in a tweet. |
| Lines of code | 3,672 | Honestly not bad for what it does. |
| Test files | **0** | Untested. Like driving without mirrors. |
| CI/CD pipelines | **0** | "Works on my machine" is the deployment strategy. |
| Force unwraps (`!`) | **34+** | Each one a tiny prayer to the crash gods. |
| Singletons | **7** | Every class is a singleton. This isn't dependency injection, it's dependency *religion*. |
| External dependencies | **0** | Not because of minimalism. Because Package.swift doesn't know what a dependency resolver is yet. |
| Config file parser | **0** | README advertises KDL config. Code has hardcoded `16` for gaps. |
| Magic numbers | **20+** | `0.95`, `0.15`, `25.0`, `100`, `10000` -- a numerology enthusiast's dream. |
| Thread safety mechanisms | **1 lock** | For 7 singletons accessed from 3+ threads. Bold. |

---

## The Seven Deadly Singletons

```swift
LayoutEngine.shared
WindowController.shared
AnimationController.shared
AXWindowObserver.shared
GestureRecognizer.shared
IPCServer.shared
Logger.shared
```

Every component is a singleton. The entire architecture is seven global variables in a trenchcoat pretending to be a design pattern. Want to test the LayoutEngine in isolation? Too bad, it's already best friends with WindowController, AnimationController, and WindowEnumerator before you even say hello. The dependency graph isn't a graph, it's a plate of spaghetti.

---

## The README-Reality Gap

The README is the most polished artifact in this repository. It has ASCII art diagrams, a comparison table dunking on PaperWM.spoon, sample KDL configuration, and skhd integration examples.

Here's what the README promises vs. what exists:

| README Claims | Reality |
|---------------|---------|
| KDL config file with live reload | `var gaps: CGFloat = 16` hardcoded in a struct |
| Window rules (`match app-id=...`) | `WindowRule` struct exists. Nothing parses or uses it. |
| `niri-macos --config ~/.config/niri-macos/config.kdl` | `main.swift` doesn't parse CLI arguments |
| "Config Manager (live reload)" in architecture diagram | No config manager exists |
| Focus ring overlay | Not implemented |
| Overview mode | Not implemented |
| Sketchybar integration | Not implemented |
| launchd plist | Not implemented |
| Homebrew formula | Not implemented |

The README is aspirational fiction. It's a vision board with a `.md` extension.

Meanwhile, `sitrep.md` -- the actual status file -- says "Core compositor logic: missing. Window management: missing. Most functionality: missing." The README and sitrep were clearly written by two different emotional states of the same developer.

---

## The Log File Situation

```swift
private let logPath = "/tmp/niri-macos.log"
```

The logger truncates the file on every launch. Hope you weren't debugging a crash from last session. Also, `fileHandle?.synchronize()` is called on every single log line, which means every log statement does a `fsync()`. In a 60fps animation loop. To `/tmp`. Performance.

---

## Socket Programming in 2026

The IPC server is hand-rolled Unix domain socket code. In Swift. With `withUnsafeMutablePointer`, `assumingMemoryBound`, and `strcpy` into a `sockaddr_un`. It's like watching someone build IKEA furniture using only a rock.

```swift
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    socketPath.withCString { cstr in
        _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
    }
}
```

There are libraries for this. There's `Network.framework` built into macOS. There's `NIO`. But no, we're `strcpy`-ing into a `sockaddr_un` by hand like it's 1997 and we're writing a CGI script.

The read buffer is 4096 bytes on the server and 8192 on the client. Why different? Nobody knows. What happens if a JSON response exceeds 4096 bytes? Also nobody knows.

---

## The Frame Matching Problem

The codebase has to match CGWindow IDs to AXUIElement references. Apple provides no direct API for this. The solution?

> Match windows by checking if their frames are within 5-10 pixels of each other.

```swift
// WindowEnumerator: tolerance of 5
abs(axFrame.origin.x - cgWindow.frame.origin.x) < 5

// AXObserver: tolerance of 10
abs(axFrame.origin.x - cgWindow.frame.origin.x) < 10
```

Two different files. Two different tolerances. For the same conceptual operation. This is the kind of heuristic that works 95% of the time and then moves your Terminal into your browser's position at 2 AM.

---

## Thread Safety: A Horror Story

The animation system runs on a `CVDisplayLink` callback at 60fps. The gesture recognizer runs on a `CGEventTap` callback. The IPC server spawns a new `Thread` for each client. The AX observer fires callbacks on... whatever thread it feels like.

All of them mutate `LayoutEngine.shared` state.

The `AnimationController` has a lock:
```swift
private let animationLock = NSLock()
```

That's it. That's the entire concurrency strategy. One lock in one class out of seven that share mutable state. The other six classes are protected by optimism.

---

## The `10000` Constant

```swift
case .focusColumnFirst:
    layoutEngine.scrollWorkspace(by: -10000)
case .focusColumnLast:
    layoutEngine.scrollWorkspace(by: 10000)
```

To scroll to the first or last column, the code scrolls by 10,000 pixels in one direction. What if you have a workspace wider than 10,000 pixels? You don't scroll to the end. What's 10,000 pixels? About 5 maximized windows on a 4K display. This will break the moment someone has 6 windows.

---

## The `space: 0` TODO

```swift
space: 0,  // TODO: Get from CGS private API
```

Every window is assigned to space 0. The entire multi-space model -- the thing that makes a scrolling window manager actually useful across desktops -- is stubbed out. The code pretends spaces exist but they're all the same space. It's like a hotel where every room key opens every door.

---

## Force Unwraps: Living Dangerously

```swift
monitors.firstIndex(where: { $0.id == monitor.id })!
```

This line is in `discoverWindows()`, a method called during initialization. If the monitor that was just verified to exist in the previous line somehow doesn't exist two lines later, the app crashes. The `guard let monitor = monitors.first` three lines above confirms it exists, and then the force unwrap asks "but does it *really*?"

The codebase treats force unwraps like semicolons in JavaScript -- technically optional, but sprinkled everywhere just in case.

---

## Documentation vs. Implementation Timeline

```
Commit 1: "feat: implement niri scrolling layout paradigm for macOS"
          (the entire project, all at once, including the README)

Commit 2: "fix: multi-monitor isolation, discrete scroll, workspace creation, split groups"
          (+2,388 lines, -129 lines. The "fix" that's bigger than the original.)
```

The second "fix" commit added the animation system, gesture recognition, AX observer, and split groups. That's not a fix, that's a sequel. The commit message undersells it like calling the Apollo program a "travel fix."

---

## Things That Are Actually Good

Credit where it's due:

- **Spring physics animation** is properly implemented. The `Spring.step(dt:)` uses real damping ratio and stiffness calculations, not lerp-and-pray.
- **The architecture diagram in the README** accurately reflects the intended design, even if half of it doesn't exist yet.
- **Zero external dependencies** means no supply chain risk and no version hell. Of course, it also means hand-rolled socket programming, but tradeoffs.
- **The IPC command set** is comprehensive and well-designed. 30+ commands covering navigation, movement, sizing, workspaces, and split groups.
- **Type modeling** in `Types.swift` is clean. `ColumnWidth` as an enum with `proportion` and `fixed` cases is the right abstraction.
- **It actually moves windows around on screen with spring animations.** In 3,672 lines. With no dependencies. That's genuinely impressive for a prototype.

---

## Prognosis

This project is a promising prototype trapped in the body of a production README. The core insight -- that niri's scrolling paradigm can work on macOS via Accessibility APIs -- appears to be valid. The spring physics are real. The IPC protocol is thoughtful. The code is organized logically even if it's held together by singletons and hope.

But it needs:
- Tests (any tests)
- Thread safety (any thread safety)
- A config parser (for the config format it already advertises)
- The 15+ features the README promises
- To stop force-unwrapping things
- To pick a single frame-matching tolerance and stick with it

**Verdict:** Not dead. Not dead *yet*. It's an impressive napkin sketch that needs to survive contact with reality, other people's machines, and any window count above 5.

---

*This autopsy was conducted with mass spectrometry-level code reading and zero survivors.*
