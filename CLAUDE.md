# Bones

A macOS tool suite for interacting with app windows via a menu bar "little guy" character. Drag him onto a window to screenshot it, click him for a fullscreen capture. Future: an AI agent sidebar that processes screenshots and builds dynamic UI overlays for interacting with any app.

## Monorepo Structure

```
desktop/     — macOS menu bar app (Swift/AppKit). The "little guy" drag-to-screenshot tool.
agent/       — Claude agent backend. Processes screenshots, powers the chat sidebar. (planned)
overlay/     — Dynamic UI layer system. Agent-generated interactive overlays on app windows. (planned)
```

## desktop/ — Menu Bar App

Native macOS app, no Xcode project. Built with `swiftc` directly.

### Build & Run

```bash
cd desktop
./build.sh
open build/Bones.app
```

### Key Files

- `Sources/AppDelegate.swift` — App lifecycle, screen recording permission check
- `Sources/StatusBarController.swift` — NSStatusItem setup, mouse event interception, right-click menu
- `Sources/DragController.swift` — Mouse tracking loop: drag threshold, floating window, highlight, drop handling
- `Sources/DragWindow.swift` — Borderless floating window showing the character during drag
- `Sources/HighlightWindow.swift` — Blue overlay on the target window during drag
- `Sources/WindowDetector.swift` — CGWindowListCopyWindowInfo hit-testing to find window under cursor
- `Sources/ScreenshotCapture.swift` — ScreenCaptureKit capture, saves PNG to Desktop + copies to clipboard
- `Sources/LittleGuyRenderer.swift` — CoreGraphics-drawn stick figure (18×18 menu bar icon + 48×48 drag avatar)
- `Sources/FeedbackWindow.swift` — HUD toast notification on successful capture
- `Info.plist` — LSUIElement=true (no Dock icon), screen capture usage description

### How It Works

1. NSStatusItem with custom button intercepts `leftMouseDown`
2. Enters a `window.nextEvent(matching:)` tracking loop (standard AppKit mouse tracking)
3. If dragged past 3px threshold: floating character + blue highlight follow cursor
4. On drop: `WindowDetector` finds window under cursor via CGWindowListCopyWindowInfo (layer==0, excludes own PID)
5. `ScreenshotCapture` uses ScreenCaptureKit to capture that specific window at Retina resolution
6. If clicked without dragging: captures fullscreen screenshot
7. Saves to ~/Desktop as PNG, copies to clipboard, plays sound, shows toast

### Permissions

- **Screen Recording** required. Granted in System Settings > Privacy & Security > Screen Recording.
- App is ad-hoc signed (`codesign --sign -`). After rebuilds, may need to toggle permission off/on.
- No Accessibility permission needed.

### Conventions

- All UI classes are `@MainActor`
- All windows use `isReleasedWhenClosed = false` to avoid ARC double-free with AppKit
- Entry point is `main.swift` using `MainActor.assumeIsolated` (Swift 6.2 concurrency)
- Menu bar icon is a template image (adapts to dark/light mode automatically)

## Conventions (All Packages)

- Each top-level directory is a self-contained package with its own build tooling
- Shared types/protocols go in a `shared/` directory if/when needed
- Screenshots are saved to `~/Desktop` with format: `Screenshot - {source} - {timestamp}.png`
- Do NOT add `Co-Authored-By` lines to git commits
