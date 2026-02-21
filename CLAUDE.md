# Bones

A macOS tool suite for interacting with app windows via a menu bar character. Drag him onto a window to open a Claude-powered chat sidebar that can see and interact with the app.

## Monorepo Structure

```
desktop/     — macOS menu bar app (Swift/AppKit). Drag-to-sidebar + AI chat.
overlay/     — Dynamic UI layer system. Agent-generated interactive overlays on app windows. (planned)
```

## desktop/ — Menu Bar App

Native macOS app, no Xcode project. Built with `swiftc` directly. See **`desktop/ARCHITECTURE.md`** for detailed file map, data flow, and guides for adding tools and modifying the sidebar.

### Build & Run

```bash
cd desktop
./build.sh
open build/Bones.app
```

### How It Works

1. User drags the menu bar character onto any app window
2. `DragController` tracks mouse, shows floating avatar + blue highlight
3. On drop: `SessionController` brings the target app forward, opens a chat sidebar
4. `ChatController` captures a screenshot and sends it to Claude (Anthropic Messages API)
5. Claude describes what it sees; user chats about the window
6. Claude has tools: `take_screenshot`, `click`, `type_text`, `scroll` — executed via CGEvent
7. If clicked without dragging: captures fullscreen screenshot to ~/Desktop

### Key Areas

- **Sidebar chat**: `SessionController` → `ChatController` → `AnthropicClient` → `SidebarWindow`
- **Drag-drop**: `StatusBarController` → `DragController` → `WindowDetector`
- **Screen capture**: `ScreenshotCapture` (ScreenCaptureKit, returns Data or saves to disk)
- **Window interaction**: `InteractionTools` (CGEvent click/type/scroll with 2x retina coordinate mapping)
- **API key**: `KeychainHelper` (macOS Keychain, first-run dialog prompt)

### Permissions

- **Screen Recording** — System Settings > Privacy & Security > Screen Recording
- **Accessibility** — System Settings > Privacy & Security > Accessibility (needed for click/type/scroll tools)
- After rebuilds, may need to toggle permissions off/on (code signature changes)

### Conventions

- All UI classes are `@MainActor`
- All windows use `isReleasedWhenClosed = false`
- Entry point is `main.swift` using `MainActor.assumeIsolated` (Swift 6.2 concurrency)
- Build with `swiftc` directly — no SPM, no Xcode. Add new `.swift` files to `build.sh`
- Menu bar icon is a template image (adapts to dark/light mode)

## Conventions (All Packages)

- Each top-level directory is a self-contained package with its own build tooling
- Shared types/protocols go in a `shared/` directory if/when needed
- Screenshots are saved to `~/Desktop` with format: `Screenshot - {source} - {timestamp}.png`
- Do NOT add `Co-Authored-By` lines to git commits
