# Bones

A macOS tool suite for interacting with app windows via a menu bar character. Drag him onto a window to open a Claude-powered chat sidebar that can see and interact with the app.

## Monorepo Structure

```
desktop/     — macOS menu bar app (Swift/AppKit). Drag-to-sidebar + AI chat.
agent/       — Python agent subprocess (anthropic SDK). Conversation loop + tool orchestration.
overlay/     — Dynamic UI layer system. Agent-generated interactive overlays on app windows. (planned)
```

## agent/ — Python Agent

The conversation loop lives in a Python subprocess (`agent/agent.py`). The Swift app launches it, communicates via JSON Lines over stdin/stdout.

### Package Management

Uses **uv** for dependency management. The venv lives at `agent/.venv/`.

```bash
cd agent
uv sync          # install/update dependencies
uv run python agent.py   # run directly (stdin/stdout IPC)
```

At runtime, `AgentBridge.swift` launches the agent via `uv run --project <agent_dir> python -u agent.py`. The `--project` flag tells uv where to find `pyproject.toml` and the `.venv/`. The build script (`desktop/build.sh`) runs `uv sync` to ensure deps are current.

### IPC Protocol

Swift ↔ Python communicate via JSON Lines (one JSON object per line):

**Swift → Python (stdin):** `init`, `user_message`, `tool_result`, `cancel`
**Python → Swift (stdout):** `streaming_start`, `text_delta`, `streaming_end`, `tool_use`, `assistant_message`, `done`, `error`
**Python stderr** → forwarded to `BoneLog`

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
4. `AgentBridge` launches Python agent subprocess, sends initial screenshot + element codes
5. Python agent calls Claude API, streams responses back to Swift for display
6. Tool calls (`click_code`, `take_screenshot`, `key_combo`, etc.) are sent to Swift for native execution
7. `ElementLabeler` assigns 2-letter Homerow codes (AA, AB, ...) to all interactable elements
8. If clicked without dragging: captures fullscreen screenshot to ~/Desktop

### Key Areas

- **Agent IPC**: `SessionController` → `AgentBridge` ↔ Python `agent.py` → Claude API
- **Sidebar chat**: `AgentBridge` → `SidebarWindow` (WebKit chat UI)
- **Element targeting**: `ElementLabeler` assigns 2-letter codes, `ScreenshotCapture.annotateWithCodes()` draws badges
- **Drag-drop**: `StatusBarController` → `DragController` → `WindowDetector`
- **Screen capture**: `ScreenshotCapture` (ScreenCaptureKit, returns Data or saves to disk)
- **Window interaction**: `InteractionTools` (CGEvent click/type/scroll/keyCombo with 2x retina coordinate mapping)
- **API key**: `KeychainHelper` (file-based at ~/.config/bones/api-key, first-run dialog prompt)

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

### Debug Logging

- Use `BoneLog.log("Component: message")` for debug logging throughout the app
- Logs write to `~/Desktop/bones-debug.log` (truncated on each app launch)
- Add generous logging in animations, physics, drag/drop, and session flows
- Prefix log messages with the component name (e.g., `DragController:`, `BoneBreak:`, `DogAnim:`)
- Python agent logs to stderr with `[agent]` prefix — forwarded to BoneLog
- Tail the log with: `tail -f ~/Desktop/bones-debug.log`

## Conventions (All Packages)

- Each top-level directory is a self-contained package with its own build tooling
- Shared types/protocols go in a `shared/` directory if/when needed
- Screenshots are saved to `~/Desktop` with format: `Screenshot - {source} - {timestamp}.png`
- Do NOT add `Co-Authored-By` lines to git commits
