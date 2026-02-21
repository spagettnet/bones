# desktop/ Architecture

Detailed guide for agents working on the desktop app. See root `CLAUDE.md` for project overview and build instructions.

## Data Flow

```
User drags Mr. Bones onto a window
  │
  ├─ DragController.beginDrag()
  │    ├─ Tracks mouse via window.nextEvent(matching:) loop
  │    ├─ Shows DragWindow (48x48 avatar) + HighlightWindow (blue overlay)
  │    └─ On drop: WindowDetector.windowAt(point:) → WindowInfo
  │
  ├─ SessionController.startSession(windowInfo:)
  │    ├─ Prompts for API key if missing (KeychainHelper)
  │    ├─ Checks Accessibility permission (InteractionTools)
  │    ├─ Brings target window to front
  │    ├─ Creates WindowTracker, ChatController, SidebarWindow
  │    └─ Calls chatController.startWithScreenshot()
  │
  └─ ChatController runs the conversation loop
       ├─ Captures screenshot via ScreenshotCapture.captureToData()
       ├─ Sends base64 PNG to Claude via AnthropicClient.streamMessages()
       ├─ Streams response tokens → updates SidebarWindow via delegate
       └─ Tool loop: if Claude calls a tool → execute → send result → repeat
```

## File Map

### Core Flow
| File | Type | Role |
|------|------|------|
| `SessionController.swift` | class | Orchestrates a sidebar session lifecycle. Owns WindowTracker + ChatController + SidebarWindow. Entry point: `startSession(windowInfo:)` |
| `ChatController.swift` | class | Conversation state + tool-use loop. Holds `conversationHistory` (API messages) and `uiMessages` (UI display). Delegates UI updates to `ChatControllerDelegate` |
| `AnthropicClient.swift` | class | URLSession HTTP client for Claude Messages API. SSE streaming via `URLSession.bytes(for:)`. Also defines shared types: `ChatMessage`, `ContentBlock`, `JSONValue`, `ToolDefinition`, `StreamEvent` |

### UI
| File | Type | Role |
|------|------|------|
| `SidebarWindow.swift` | NSPanel | Chat UI. 340px wide, floats beside target window. Message bubbles + text input. Implements `ChatControllerDelegate`. Contains `NSFlippedView` helper class |
| `StatusBarController.swift` | class | Menu bar icon + right-click menu. Creates SessionController and DragController |
| `DragController.swift` | class | Mouse tracking loop for drag-to-drop. On drop calls `sessionController.startSession()` |
| `DragWindow.swift` | NSWindow | 48x48 floating character during drag |
| `HighlightWindow.swift` | NSWindow | Blue overlay on target window during drag |
| `FeedbackWindow.swift` | NSWindow | HUD toast (used by fullscreen capture, not sidebar flow) |

### Services
| File | Type | Role |
|------|------|------|
| `ScreenshotCapture.swift` | enum | ScreenCaptureKit capture. `capture(windowID:)` saves to disk. `captureToData(windowID:)` returns PNG `Data` for API |
| `WindowDetector.swift` | enum | Finds window under cursor via `CGWindowListCopyWindowInfo`. Returns `WindowInfo` struct |
| `WindowTracker.swift` | class | Polls target window position every 100ms. Fires `onBoundsChanged` / `onWindowClosed` callbacks |
| `InteractionTools.swift` | enum | CGEvent-based click, type, scroll. Coordinate mapping from 2x retina image pixels to screen points |
| `KeychainHelper.swift` | enum | Stores/retrieves API key in macOS Keychain. Shows first-run prompt dialog |
| `LittleGuyRenderer.swift` | enum | CoreGraphics-drawn stick figure for menu bar (18x18) and drag avatar (48x48) |

## How to Add a New Tool

Tools are defined in two places and executed in a third:

### 1. Define the tool schema in `ChatController.swift`

Add a `ToolDefinition` to the `toolDefinitions` computed property (~line 50):

```swift
ToolDefinition(
    name: "my_tool",
    description: "What Claude should know about when to use this tool.",
    inputSchema: ToolSchema(
        properties: [
            "param1": ToolProperty(type: "string", description: "...", enumValues: nil),
            "param2": ToolProperty(type: "integer", description: "...", enumValues: nil)
        ],
        required: ["param1"]
    )
)
```

Supported `type` values: `"string"`, `"integer"`, `"number"`, `"boolean"`. Add `enumValues` for constrained choices.

### 2. Handle execution in `ChatController.executeTool()`

Add a case to the switch in `executeTool(name:input:toolId:)` (~line 238):

```swift
case "my_tool":
    let param1 = input["param1"]?.stringValue ?? ""
    let param2 = input["param2"]?.intValue ?? 0
    // Do the work...
    return .toolResult(toolUseId: toolId, content: [.text("Result message")], isError: false)
```

Tool results can include images: `.image(mediaType: "image/png", base64Data: base64String)`.

### 3. Implement the actual logic

For simple tools, inline the logic in the switch case. For complex tools, add a static method to `InteractionTools.swift` or create a new file (remember to add it to `build.sh`).

### Tool execution context

Inside `executeTool()`, you have access to:
- `currentContext` — `TargetContext` with the target window's current bounds, PID, windowID
- `windowTracker` — for getting live window position
- `ScreenshotCapture.captureToData(windowID:)` — for taking screenshots

### Coordinate system

Claude sees screenshots at **2x retina pixel dimensions**. A 800x600pt window produces a 1600x1200px image. When Claude returns coordinates (e.g., for click), they are in this pixel space. `InteractionTools.screenPoint(fromImageX:imageY:context:)` converts them:
- Divide by `retinaScale` (2.0) to get window-relative logical points
- Add window origin (CG coordinates, top-left) to get absolute screen point

## How to Modify the Sidebar UI

The sidebar is in `SidebarWindow.swift`. Key areas:

### Layout
- `setupUI()` builds the view hierarchy: `NSVisualEffectView` background → `NSScrollView` for messages → input area at bottom
- `messageContainer` is an `NSFlippedView` (y=0 is top) so messages stack top-to-bottom
- Input area is 44px tall at the bottom with an `NSTextField` and send button

### Message rendering
- `rebuildMessageViews()` clears and re-creates all bubble views on every update (simple but not optimized for large conversations)
- `createBubble(for:containerWidth:yOffset:)` builds individual message bubbles:
  - User messages: blue background, right-aligned
  - Assistant messages: gray background, left-aligned
  - Text is rendered as rich markdown in `NSTextView` via `renderMarkdown()`
- Streaming messages show `" ..."` suffix

### Markdown rendering
- `renderMarkdown(_:baseColor:)` converts Claude's markdown output to `NSAttributedString`
- Uses `AttributedString(markdown:options: .inlineOnlyPreservingWhitespace)` (macOS 12+)
- Walks the parsed result to apply correct fonts at 13pt: bold, italic, monospace for inline code
- Inline code gets a subtle `.backgroundColor` highlight
- Fallback `renderCodeBlocks()` handles fenced ``` code blocks manually when the system parser can't

### Delegate callbacks
`ChatControllerDelegate` has two methods:
- `chatControllerDidUpdateMessages(_:)` — called on every text delta, tool start, message complete
- `chatControllerDidEncounterError(_:error:)` — shows an NSAlert

### Window positioning
- `sidebarFrame(forTargetBounds:sidebarWidth:)` computes sidebar position: right edge of target + 4px gap, matching target height
- Converts from CG coordinates (top-left origin) to AppKit coordinates (bottom-left origin)
- `WindowTracker.onBoundsChanged` repositions the sidebar when the target window moves

## API Client Details

`AnthropicClient.swift` handles all Claude API communication.

### Types
- `ChatMessage` — role + array of `ContentBlock`
- `ContentBlock` — enum: `.text(String)`, `.image(mediaType, base64Data)`, `.toolUse(id, name, input)`, `.toolResult(toolUseId, content, isError)`
- `JSONValue` — lightweight JSON enum with `.stringValue` and `.intValue` accessors
- `StreamEvent` — SSE events: `contentBlockStart`, `textDelta`, `inputJsonDelta`, `contentBlockStop`, `messageDelta`, `messageStop`, `error`

### Streaming
- Uses `URLSession.bytes(for:)` → reads SSE lines in `Task.detached` (off main actor)
- `parseSSEEvent()` is `nonisolated` so it can run off-main
- Returns `AsyncStream<StreamEvent>` consumed by ChatController on MainActor

### JSON encoding
Manual via `JSONSerialization` (no Codable). `encodeMessage()` / `encodeContentBlock()` / `encodeTool()` are all static methods. This keeps things flexible and avoids CodingKey boilerplate for the snake_case API.

### Auth
- Header: `x-api-key: {key}` (not Bearer token)
- Header: `anthropic-version: 2023-06-01`
- Model default: `claude-sonnet-4-5-20250929`

## Permissions

The app needs two macOS permissions:

| Permission | Why | How to grant |
|---|---|---|
| Screen Recording | ScreenCaptureKit screenshot capture | System Settings > Privacy & Security > Screen Recording |
| Accessibility | CGEvent posting (click, type, scroll) | System Settings > Privacy & Security > Accessibility |

After rebuilding, you may need to toggle permissions off/on because the code signature changes.

## Build System

`build.sh` compiles all Swift files with `swiftc` directly (no SPM, no Xcode). When adding a new `.swift` file:

1. Create the file in `Sources/`
2. Add it to the `swiftc` command in `build.sh`
3. Frameworks currently linked: `AppKit`, `ScreenCaptureKit`, `CoreGraphics`, `Security`
4. If you need a new framework, add `-framework FrameworkName` to `build.sh`

All source files are compiled together — there are no modules, so all types are visible to all files without `import`.
