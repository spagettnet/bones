import Foundation

struct GetAccessibilityTreeTool: AgentTool {
    let name = "get_accessibility_tree"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get the full accessibility tree of the target window as JSON. Returns a nested tree of UI elements with roles, labels, values, and positions. Use this to understand the app's UI structure.",
            inputSchema: ToolSchema(properties: [:], required: [])
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let tree = ActiveAppState.shared.contextTree else {
            return .toolResult(toolUseId: toolId, content: [.text("No accessibility tree available. The target window may not be accessible.")], isError: true)
        }
        let json = tree.toJSON()
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            return .toolResult(toolUseId: toolId, content: [.text("Failed to serialize accessibility tree")], isError: true)
        }
        return .toolResult(toolUseId: toolId, content: [.text(jsonString)], isError: false)
    }
}
