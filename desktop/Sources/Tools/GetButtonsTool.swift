import Foundation

struct GetButtonsTool: AgentTool {
    let name = "get_buttons"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get all clickable buttons/controls in the target window. Returns an array of elements with role, label, and frame (in screen coordinates). Use click_element to click them by label.",
            inputSchema: ToolSchema(properties: [:], required: [])
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let buttons = ActiveAppState.shared.buttons
        if buttons.isEmpty {
            return .toolResult(toolUseId: toolId, content: [.text("No buttons found in the target window.")], isError: false)
        }
        let items = buttons.map { node -> [String: Any] in
            var item: [String: Any] = ["role": node.role]
            item["label"] = node.title ?? node.description ?? node.roleDescription
            if let f = node.frame {
                item["frame"] = ["x": Int(f.origin.x), "y": Int(f.origin.y), "w": Int(f.width), "h": Int(f.height)]
            }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return .toolResult(toolUseId: toolId, content: [.text("Failed to serialize buttons")], isError: true)
        }
        return .toolResult(toolUseId: toolId, content: [.text("Found \(buttons.count) buttons:\n\(jsonString)")], isError: false)
    }
}
