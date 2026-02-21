import Foundation
import AppKit

// MARK: - UI Message Model

struct ChatOption {
    let label: String
    let value: String
}

struct ChatMessageUI {
    let id: UUID
    let role: MessageRole
    var text: String
    var isStreaming: Bool
    var isStatus: Bool = false
    var options: [ChatOption]? = nil
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
    private let executionContext: ToolExecutionContext
    private let toolRegistry: ToolRegistry
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?

    var systemPrompt = """
        You are an AI assistant that can see and interact with the user's screen. \
        You are looking at a specific application window.

        CRITICAL — How to interact with the app:
        When the user asks you to click something, type into something, or interact with any UI element:
        1. Use find_elements(query) to search the accessibility tree for that element. Try different search terms \
        if the first doesn't work (e.g. "source control", "git", "scm", "branch").
        2. Use click_element(label) to click the found element by its label. This clicks the exact center of the \
        element using its accessibility frame — it is precise and never misses.
        3. Use type_into_field(label, text) to type into input fields by label.
        4. Use take_screenshot to verify the result after actions.

        NEVER guess or estimate pixel coordinates. NEVER use the raw click(x,y) tool unless find_elements confirms \
        there is no accessibility data for the target. The accessibility tree knows the exact position of every element.

        For discovery:
        - find_elements(query) — search the tree by keyword (FAST, use this first)
        - get_buttons / get_input_fields — list all buttons or inputs
        - take_screenshot with labeled=true — visual screenshot with numbered element badges
        - get_accessibility_tree — full tree dump (LARGE, use only if find_elements isn't enough)

        Always briefly describe what you see before and after taking actions.
        """

    init(apiKey: String, executionContext: ToolExecutionContext, toolRegistry: ToolRegistry) {
        self.client = AnthropicClient(apiKey: apiKey)
        self.executionContext = executionContext
        self.toolRegistry = toolRegistry
    }

    // MARK: - Public Interface

    var isCurrentlyProcessing: Bool { isProcessing }

    func startWithScreenshot() async {
        guard let imageData = await ScreenshotCapture.captureToData(windowID: executionContext.windowID) else {
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

    func cancelProcessing() {
        guard isProcessing else { return }
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false

        // Mark any streaming messages as done and append a cancellation notice
        for i in uiMessages.indices {
            if uiMessages[i].isStreaming {
                uiMessages[i].isStreaming = false
            }
        }
        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .assistant, text: "[Stopped]", isStreaming: false
        ))
        delegate?.chatControllerDidUpdateMessages(self)
        BoneLog.log("ChatController: processing cancelled by user")
    }

    // MARK: - Tool Loop

    private func sendAndProcessResponse() async {
        isProcessing = true
        let task = Task { @MainActor in
            await self.processResponseLoop()
        }
        currentTask = task
        await task.value
        currentTask = nil
        isProcessing = false
    }

    private func processResponseLoop() async {
        var loopCount = 0
        let maxLoops = 20

        while loopCount < maxLoops {
            guard !Task.isCancelled else { return }
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
                conversationHistory, system: systemPrompt, tools: toolRegistry.definitions
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
                guard !Task.isCancelled else { return }
                var toolResults: [ContentBlock] = []
                for tool in toolUseBlocks {
                    guard !Task.isCancelled else { return }
                    let input = parseToolInput(tool.jsonAccumulator)

                    // Show tool execution in UI
                    uiMessages.append(ChatMessageUI(
                        id: UUID(), role: .assistant,
                        text: "Using \(tool.name)...",
                        isStreaming: false
                    ))
                    delegate?.chatControllerDidUpdateMessages(self)

                    let result = await toolRegistry.execute(name: tool.name, input: input, toolId: tool.id, context: executionContext)
                    toolResults.append(result)
                }
                conversationHistory.append(ChatMessage(role: .user, content: toolResults))
            } else {
                break
            }
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
