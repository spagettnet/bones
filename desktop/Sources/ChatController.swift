import Foundation
import AppKit

// MARK: - UI Message Model

struct ChatMessageUI {
    let id: UUID
    let role: MessageRole
    var text: String
    var isStreaming: Bool
    var visualizationHTML: String? = nil
    var visualizationTitle: String? = nil
}

// MARK: - Delegate

protocol ChatControllerDelegate: AnyObject {
    @MainActor func chatControllerDidUpdateMessages(_ controller: ChatController)
    @MainActor func chatControllerDidEncounterError(_ controller: ChatController, error: String)
}

// MARK: - ChatController

@MainActor
class ChatController {
    weak var delegate: ChatControllerDelegate?
    private let client: AnthropicClient
    private var conversationHistory: [ChatMessage] = []
    private(set) var uiMessages: [ChatMessageUI] = []
    private let targetContext: TargetContext
    private let windowTracker: WindowTracker
    private let widgetManager: WidgetManager?
    private var isProcessing = false
    var isBusy: Bool { isProcessing }

    private let systemPrompt = """
        You are an AI assistant that can see and interact with the user's screen. \
        You are looking at a specific application window. Use the available tools to help the user. \
        After performing actions like click, type, or scroll, take a screenshot to verify the result. \
        Coordinates in screenshots are in pixel space (2x retina). The image dimensions are 2x the \
        logical window size. For example, if a button appears at pixel (400, 300) in the screenshot, \
        pass x=400, y=300 to the click tool. \
        Always briefly describe what you see before and after taking actions. \
        When looking at a code editor (VS Code, Cursor, Xcode, etc.), use read_editor_content to get \
        the full source code text instead of relying only on screenshots. \
        Use the visualize tool to show the user visual mockups, UI renderings, component previews, \
        diagrams, or any visual content as interactive HTML in the sidebar.
        """

    init(apiKey: String, targetContext: TargetContext, windowTracker: WindowTracker, widgetManager: WidgetManager? = nil) {
        self.client = AnthropicClient(apiKey: apiKey)
        self.targetContext = targetContext
        self.windowTracker = windowTracker
        self.widgetManager = widgetManager
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [ToolDefinition] {
        [
            ToolDefinition(
                name: "take_screenshot",
                description: "Take a screenshot of the target application window. Returns the current screenshot.",
                inputSchema: ToolSchema(properties: [:], required: [])
            ),
            ToolDefinition(
                name: "click",
                description: "Click at a position in the target window. Coordinates are in image pixel space (2x retina).",
                inputSchema: ToolSchema(
                    properties: [
                        "x": ToolProperty(type: "integer", description: "X coordinate in image pixels", enumValues: nil),
                        "y": ToolProperty(type: "integer", description: "Y coordinate in image pixels", enumValues: nil)
                    ],
                    required: ["x", "y"]
                )
            ),
            ToolDefinition(
                name: "type_text",
                description: "Type text at the current cursor position in the target window.",
                inputSchema: ToolSchema(
                    properties: [
                        "text": ToolProperty(type: "string", description: "Text to type", enumValues: nil)
                    ],
                    required: ["text"]
                )
            ),
            ToolDefinition(
                name: "scroll",
                description: "Scroll at a position in the target window.",
                inputSchema: ToolSchema(
                    properties: [
                        "x": ToolProperty(type: "integer", description: "X coordinate in image pixels", enumValues: nil),
                        "y": ToolProperty(type: "integer", description: "Y coordinate in image pixels", enumValues: nil),
                        "direction": ToolProperty(type: "string", description: "Scroll direction", enumValues: ["up", "down"]),
                        "amount": ToolProperty(type: "integer", description: "Number of scroll clicks (default 3)", enumValues: nil)
                    ],
                    required: ["x", "y", "direction"]
                )
            ),
            ToolDefinition(
                name: "show_widget",
                description: "Show a floating widget panel at a position on the target window. Use to display contextual information like color swatches, JSON viewers, code snippets, or custom HTML widgets.",
                inputSchema: ToolSchema(properties: [:], required: []),
                rawInputSchema: [
                    "type": "object",
                    "properties": [
                        "widget_id": ["type": "string", "description": "Unique ID for this widget (e.g. 'color1', 'json-data')"],
                        "type": ["type": "string", "description": "Widget type", "enum": ["color_swatch", "json_viewer", "code_snippet", "custom_html"]],
                        "x": ["type": "integer", "description": "X position in image pixels (2x retina)"],
                        "y": ["type": "integer", "description": "Y position in image pixels (2x retina)"],
                        "title": ["type": "string", "description": "Title for the widget window"],
                        "config": [
                            "type": "object",
                            "description": "Widget configuration. For color_swatch: {color: '#hex'}. For json_viewer: {json: '{...}'}. For code_snippet: {code: '...', language: 'swift'}. For custom_html: {html: '<div>...</div>', width: 300, height: 200}."
                        ]
                    ] as [String: Any],
                    "required": ["widget_id", "type", "x", "y", "title", "config"]
                ]
            ),
            ToolDefinition(
                name: "dismiss_widget",
                description: "Dismiss a floating widget panel. Use widget_id='all' to dismiss all widgets.",
                inputSchema: ToolSchema(
                    properties: [
                        "widget_id": ToolProperty(type: "string", description: "ID of widget to dismiss, or 'all' for all widgets", enumValues: nil)
                    ],
                    required: ["widget_id"]
                name: "read_editor_content",
                description: "Read the full text content from the focused text area or code editor in the target window. Returns the complete file/document text, not just what's visible on screen. Use this on code editors (VS Code, Cursor, Xcode, etc.) to get the actual source code.",
                inputSchema: ToolSchema(properties: [:], required: [])
            ),
            ToolDefinition(
                name: "visualize",
                description: "Render an interactive HTML visualization in the chat sidebar. Use this to show visual representations of UI components, widgets, mockups, diagrams, or any visual content. Provide complete HTML with inline CSS and JS. The content renders in a sandboxed frame within the sidebar.",
                inputSchema: ToolSchema(
                    properties: [
                        "html": ToolProperty(type: "string", description: "Complete HTML content to render (can include inline <style> and <script> tags)", enumValues: nil),
                        "title": ToolProperty(type: "string", description: "Label shown above the visualization", enumValues: nil)
                    ],
                    required: ["html"]
                )
            )
        ]
    }

    // MARK: - Public Interface

    func startWithScreenshot() async {
        guard let imageData = await ScreenshotCapture.captureToData(windowID: targetContext.windowID) else {
            delegate?.chatControllerDidEncounterError(self, error: "Failed to capture initial screenshot")
            return
        }
        ActiveAppState.shared.recordScreenshot(filename: "Initial session capture")

        let base64 = imageData.base64EncodedString()
        let userContent: [ContentBlock] = [
            .image(mediaType: "image/png", base64Data: base64),
            .text("Here is the current state of the window. What do you see?")
        ]
        conversationHistory.append(ChatMessage(role: .user, content: userContent))

        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .user,
            text: "[Screenshot sent] What do you see?",
            isStreaming: false
        ))
        delegate?.chatControllerDidUpdateMessages(self)

        await sendAndProcessResponse()
    }

    func injectContentChange(imageData: Data) async {
        guard !isProcessing else {
            BoneLog.log("ChatController: skipping content change injection — busy")
            return
        }

        let base64 = imageData.base64EncodedString()
        let userContent: [ContentBlock] = [
            .image(mediaType: "image/png", base64Data: base64),
            .text("The window content has changed. Here is the updated view.")
        ]
        conversationHistory.append(ChatMessage(role: .user, content: userContent))

        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .user,
            text: "[Content changed — new screenshot sent]",
            isStreaming: false
        ))
        delegate?.chatControllerDidUpdateMessages(self)

        await sendAndProcessResponse()
    }

    func sendUserMessage(_ text: String) async {
        guard !isProcessing else { return }

        conversationHistory.append(ChatMessage(role: .user, content: [.text(text)]))
        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .user, text: text, isStreaming: false
        ))
        delegate?.chatControllerDidUpdateMessages(self)

        await sendAndProcessResponse()
    }

    // MARK: - Tool Loop

    private func sendAndProcessResponse() async {
        isProcessing = true
        var loopCount = 0
        let maxLoops = 20

        while loopCount < maxLoops {
            loopCount += 1

            // Add streaming assistant message placeholder
            let msgIndex = uiMessages.count
            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant, text: "", isStreaming: true
            ))
            delegate?.chatControllerDidUpdateMessages(self)

            // Accumulate response
            var textAccumulator = ""
            var toolUseBlocks: [(id: String, name: String, jsonAccumulator: String)] = []
            var currentToolIndex: Int? = nil
            var stopReason: String? = nil

            let stream = client.streamMessages(
                conversationHistory, system: systemPrompt, tools: toolDefinitions
            )

            for await event in stream {
                switch event {
                case .contentBlockStart(_, let type, let toolUseId, let toolName):
                    if type == "tool_use", let id = toolUseId, let name = toolName {
                        toolUseBlocks.append((id: id, name: name, jsonAccumulator: ""))
                        currentToolIndex = toolUseBlocks.count - 1
                    }

                case .textDelta(_, let text):
                    textAccumulator += text
                    uiMessages[msgIndex].text = textAccumulator
                    delegate?.chatControllerDidUpdateMessages(self)

                case .inputJsonDelta(_, let json):
                    if let idx = currentToolIndex {
                        toolUseBlocks[idx].jsonAccumulator += json
                    }

                case .contentBlockStop(_):
                    currentToolIndex = nil

                case .messageDelta(let reason):
                    stopReason = reason

                case .error(let msg):
                    uiMessages[msgIndex].isStreaming = false
                    uiMessages[msgIndex].text = textAccumulator.isEmpty ? "Error: \(msg)" : textAccumulator + "\n\nError: \(msg)"
                    delegate?.chatControllerDidUpdateMessages(self)
                    isProcessing = false
                    return

                default:
                    break
                }
            }

            uiMessages[msgIndex].isStreaming = false
            delegate?.chatControllerDidUpdateMessages(self)

            // Build API-level assistant message
            var assistantContent: [ContentBlock] = []
            if !textAccumulator.isEmpty {
                assistantContent.append(.text(textAccumulator))
            }
            for tool in toolUseBlocks {
                let input = parseToolInput(tool.jsonAccumulator)
                assistantContent.append(.toolUse(id: tool.id, name: tool.name, input: input))
            }
            if !assistantContent.isEmpty {
                conversationHistory.append(ChatMessage(role: .assistant, content: assistantContent))
            }

            // If tool use, execute and loop
            if stopReason == "tool_use" && !toolUseBlocks.isEmpty {
                var toolResults: [ContentBlock] = []
                for tool in toolUseBlocks {
                    let input = parseToolInput(tool.jsonAccumulator)

                    // Show tool execution in UI
                    uiMessages.append(ChatMessageUI(
                        id: UUID(), role: .assistant,
                        text: "Using \(tool.name)...",
                        isStreaming: false
                    ))
                    delegate?.chatControllerDidUpdateMessages(self)

                    let result = await executeTool(name: tool.name, input: input, toolId: tool.id)
                    toolResults.append(result)
                }
                conversationHistory.append(ChatMessage(role: .user, content: toolResults))
            } else {
                break
            }
        }

        isProcessing = false
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, input: [String: JSONValue], toolId: String) async -> ContentBlock {
        let currentContext = TargetContext(
            windowID: targetContext.windowID,
            ownerPID: targetContext.ownerPID,
            bounds: windowTracker.currentBounds(),
            retinaScale: targetContext.retinaScale
        )

        switch name {
        case "take_screenshot":
            guard let imageData = await ScreenshotCapture.captureToData(windowID: currentContext.windowID) else {
                return .toolResult(toolUseId: toolId, content: [.text("Screenshot failed")], isError: true)
            }
            let base64 = imageData.base64EncodedString()
            return .toolResult(
                toolUseId: toolId,
                content: [.image(mediaType: "image/png", base64Data: base64)],
                isError: false
            )

        case "click":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let result = await InteractionTools.click(x: x, y: y, context: currentContext)
            return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)

        case "type_text":
            let text = input["text"]?.stringValue ?? ""
            let result = await InteractionTools.typeText(text, context: currentContext)
            return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)

        case "scroll":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let direction = input["direction"]?.stringValue ?? "down"
            let amount = input["amount"]?.intValue ?? 3
            let result = await InteractionTools.scroll(x: x, y: y, direction: direction, amount: amount, context: currentContext)
            return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)

        case "show_widget":
            guard let wm = widgetManager else {
                return .toolResult(toolUseId: toolId, content: [.text("Widget manager not available")], isError: true)
            }
            let widgetId = input["widget_id"]?.stringValue ?? "widget-\(UUID().uuidString.prefix(8))"
            let type = input["type"]?.stringValue ?? "custom_html"
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let title = input["title"]?.stringValue ?? "Widget"
            var config: [String: Any] = [:]
            if case .object(let configObj) = input["config"] {
                for (k, v) in configObj {
                    config[k] = jsonValueToAny(v)
                }
            }
            let result = wm.showWidget(id: widgetId, type: type, x: x, y: y, title: title, config: config)
            return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)

        case "dismiss_widget":
            guard let wm = widgetManager else {
                return .toolResult(toolUseId: toolId, content: [.text("Widget manager not available")], isError: true)
            }
            let widgetId = input["widget_id"]?.stringValue ?? "all"
            let result = wm.dismissWidget(id: widgetId)
            return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)
        case "read_editor_content":
            BoneLog.log("ChatController: read_editor_content — pid=\(currentContext.ownerPID)")
            let textResults = AccessibilityHelper.readTextContent(pid: currentContext.ownerPID, bounds: currentContext.bounds)
            if textResults.isEmpty {
                return .toolResult(toolUseId: toolId, content: [.text("No text area found in the target window. The app may not expose text content via accessibility, or no editor is focused.")], isError: false)
            }
            var output = ""
            for (i, r) in textResults.enumerated() {
                if textResults.count > 1 {
                    output += "--- Text Area \(i + 1) (\(r.role)\(r.title.map { ": \($0)" } ?? "")) ---\n"
                }
                output += r.text
                if r.wasTruncated {
                    output += "\n\n[Truncated — total \(r.characterCount) characters, showing first 100,000]"
                }
                output += "\n"
            }
            return .toolResult(toolUseId: toolId, content: [.text(output)], isError: false)

        case "visualize":
            let html = input["html"]?.stringValue ?? ""
            let vizTitle = input["title"]?.stringValue
            guard !html.isEmpty else {
                return .toolResult(toolUseId: toolId, content: [.text("Error: html parameter is required")], isError: true)
            }
            BoneLog.log("ChatController: visualize — title=\(vizTitle ?? "none"), html length=\(html.count)")
            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant,
                text: "",
                isStreaming: false,
                visualizationHTML: html,
                visualizationTitle: vizTitle
            ))
            delegate?.chatControllerDidUpdateMessages(self)
            return .toolResult(toolUseId: toolId, content: [.text("Visualization rendered in sidebar\(vizTitle.map { ": \($0)" } ?? "")")], isError: false)

        default:
            return .toolResult(toolUseId: toolId, content: [.text("Unknown tool: \(name)")], isError: true)
        }
    }

    // MARK: - Helpers

    private func parseToolInput(_ jsonString: String) -> [String: JSONValue] {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [String: JSONValue] = [:]
        for (key, value) in obj {
            result[key] = convertToJSONValue(value)
        }
        return result
    }

    private func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { jsonValueToAny($0) }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = jsonValueToAny(v) }
            return result
        }
    }

    private func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let s as String: return .string(s)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let b as Bool: return .bool(b)
        case let arr as [Any]: return .array(arr.map { convertToJSONValue($0) })
        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (k, v) in dict { result[k] = convertToJSONValue(v) }
            return .object(result)
        default: return .null
        }
    }
}
