import Foundation

// MARK: - API Data Types

enum MessageRole: String, Codable {
    case user, assistant
}

struct ChatMessage {
    let role: MessageRole
    let content: [ContentBlock]
}

enum ContentBlock {
    case text(String)
    case image(mediaType: String, base64Data: String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: [ContentBlock], isError: Bool)
}

enum JSONValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: ToolSchema
}

struct ToolSchema {
    let properties: [String: ToolProperty]
    let required: [String]
}

struct ToolProperty {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: ToolPropertyItems?

    init(type: String, description: String, enumValues: [String]? = nil, items: ToolPropertyItems? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

struct ToolPropertyItems {
    let type: String
}

// MARK: - Stream Events

enum StreamEvent {
    case contentBlockStart(index: Int, type: String, toolUseId: String?, toolName: String?)
    case textDelta(index: Int, text: String)
    case inputJsonDelta(index: Int, json: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageStop
    case error(String)
}

// MARK: - Anthropic Client

@MainActor
class AnthropicClient {
    let model: String
    let maxTokens: Int
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private var apiKey: String

    init(apiKey: String, model: String = "claude-sonnet-4-5-20250929", maxTokens: Int = 4096) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    func streamMessages(
        _ messages: [ChatMessage],
        system: String?,
        tools: [ToolDefinition]?
    ) -> AsyncStream<StreamEvent> {
        let requestBody = buildRequestJSON(messages, system: system, tools: tools, stream: true)
        let request = buildHTTPRequest(body: requestBody)

        return AsyncStream { continuation in
            Task.detached { [request] in
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.yield(.error("HTTP \(httpResponse.statusCode): \(errorBody)"))
                        continuation.finish()
                        return
                    }

                    var eventType = ""
                    var dataBuffer = ""

                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            eventType = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            dataBuffer = String(line.dropFirst(6))
                            // Process complete event
                            let events = Self.parseSSEEvent(type: eventType, data: dataBuffer)
                            for event in events {
                                continuation.yield(event)
                            }
                            dataBuffer = ""
                        } else if line.isEmpty {
                            eventType = ""
                            dataBuffer = ""
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error("Network error: \(error.localizedDescription)"))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildHTTPRequest(body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildRequestJSON(
        _ messages: [ChatMessage],
        system: String?,
        tools: [ToolDefinition]?,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": stream
        ]

        if let system = system {
            body["system"] = system
        }

        body["messages"] = messages.map { Self.encodeMessage($0) }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { Self.encodeTool($0) }
        }

        return body
    }

    // MARK: - JSON Encoding (manual, no Codable to keep flexible)

    private static func encodeMessage(_ message: ChatMessage) -> [String: Any] {
        return [
            "role": message.role.rawValue,
            "content": message.content.map { encodeContentBlock($0) }
        ]
    }

    private static func encodeContentBlock(_ block: ContentBlock) -> [String: Any] {
        switch block {
        case .text(let text):
            return ["type": "text", "text": text]
        case .image(let mediaType, let base64Data):
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64Data
                ]
            ]
        case .toolUse(let id, let name, let input):
            return [
                "type": "tool_use",
                "id": id,
                "name": name,
                "input": encodeJSONValue(.object(input))
            ]
        case .toolResult(let toolUseId, let content, let isError):
            var dict: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": toolUseId,
                "content": content.map { encodeContentBlock($0) }
            ]
            if isError {
                dict["is_error"] = true
            }
            return dict
        }
    }

    private static func encodeTool(_ tool: ToolDefinition) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (key, prop) in tool.inputSchema.properties {
            var propDict: [String: Any] = [
                "type": prop.type,
                "description": prop.description
            ]
            if let enumVals = prop.enumValues {
                propDict["enum"] = enumVals
            }
            if let items = prop.items {
                propDict["items"] = ["type": items.type]
            }
            properties[key] = propDict
        }

        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": tool.inputSchema.required
            ]
        ]
    }

    private static func encodeJSONValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { encodeJSONValue($0) }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = encodeJSONValue(v) }
            return result
        }
    }

    // MARK: - SSE Parsing

    nonisolated private static func parseSSEEvent(type: String, data: String) -> [StreamEvent] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return [] }

        switch type {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String
            else { return [] }

            let toolUseId = block["id"] as? String
            let toolName = block["name"] as? String
            return [.contentBlockStart(index: index, type: blockType, toolUseId: toolUseId, toolName: toolName)]

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String
            else { return [] }

            switch deltaType {
            case "text_delta":
                if let text = delta["text"] as? String {
                    return [.textDelta(index: index, text: text)]
                }
            case "input_json_delta":
                if let partial = delta["partial_json"] as? String {
                    return [.inputJsonDelta(index: index, json: partial)]
                }
            default:
                break
            }
            return []

        case "content_block_stop":
            if let index = json["index"] as? Int {
                return [.contentBlockStop(index: index)]
            }
            return []

        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            let stopReason = delta?["stop_reason"] as? String
            return [.messageDelta(stopReason: stopReason)]

        case "message_stop":
            return [.messageStop]

        case "error":
            let errorInfo = json["error"] as? [String: Any]
            let message = errorInfo?["message"] as? String ?? "Unknown API error"
            return [.error(message)]

        default:
            return []
        }
    }
}
