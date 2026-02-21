import Foundation

struct GetInputFieldsTool: AgentTool {
    let name = "get_input_fields"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get all input fields (text fields, search boxes, text areas) in the target window. Returns an array of elements with role, label, current value, and frame. Use type_into_field to type into them by label.",
            inputSchema: ToolSchema(properties: [:], required: [])
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let inputs = ActiveAppState.shared.inputFields
        if inputs.isEmpty {
            return .toolResult(toolUseId: toolId, content: [.text("No input fields found in the target window.")], isError: false)
        }
        let items = inputs.map { node -> [String: Any] in
            var item: [String: Any] = ["role": node.role]
            item["label"] = node.title ?? node.description ?? node.roleDescription
            item["value"] = node.value
            if let f = node.frame {
                item["frame"] = ["x": Int(f.origin.x), "y": Int(f.origin.y), "w": Int(f.width), "h": Int(f.height)]
            }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return .toolResult(toolUseId: toolId, content: [.text("Failed to serialize input fields")], isError: true)
        }
        return .toolResult(toolUseId: toolId, content: [.text("Found \(inputs.count) input fields:\n\(jsonString)")], isError: false)
    }
}
