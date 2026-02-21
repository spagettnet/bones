import Foundation
import AppKit

// MARK: - UI Message Model

struct ChatMessageUI {
    let id: UUID
    let role: MessageRole
    var text: String
    var isStreaming: Bool
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
    private var isProcessing = false

    private let systemPrompt = """
        You are an AI assistant that can see and interact with the user's screen. \
        You are looking at a specific application window. Use the available tools to help the user. \
        After performing actions like click, type, or scroll, take a screenshot to verify the result. \
        Coordinates in screenshots are in pixel space (2x retina). The image dimensions are 2x the \
        logical window size. For example, if a button appears at pixel (400, 300) in the screenshot, \
        pass x=400, y=300 to the click tool. \
        Always briefly describe what you see before and after taking actions.
        """

    init(apiKey: String, targetContext: TargetContext, windowTracker: WindowTracker) {
        self.client = AnthropicClient(apiKey: apiKey)
        self.targetContext = targetContext
        self.windowTracker = windowTracker
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
            )
        ]
    }

    // MARK: - Public Interface

    func startWithScreenshot() async {
        guard let imageData = await ScreenshotCapture.captureToData(windowID: targetContext.windowID) else {
            delegate?.chatControllerDidEncounterError(self, error: "Failed to capture initial screenshot")
            return
        }

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
