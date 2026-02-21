import Foundation

struct UpdateOverlayTool: AgentTool {
    let name = "update_overlay"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Update the current overlay. Use 'html' for a full replacement or 'javascript' for a partial state-preserving update.",
            inputSchema: ToolSchema(
                properties: [
                    "html": ToolProperty(type: "string", description: "New HTML content (full replacement)", enumValues: nil),
                    "javascript": ToolProperty(type: "string", description: "JavaScript to execute in the overlay (partial update, preserves state)", enumValues: nil)
                ],
                required: []
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let overlayManager = context.overlayManager else {
            return .toolResult(toolUseId: toolId, content: [.text("Overlay system not available")], isError: true)
        }
        guard overlayManager.hasOverlay else {
            return .toolResult(toolUseId: toolId, content: [.text("No overlay is currently active. Use create_overlay first.")], isError: true)
        }

        if let html = input["html"]?.stringValue {
            overlayManager.updateOverlay(html: html)
            return .toolResult(toolUseId: toolId, content: [.text("Overlay updated with new HTML")], isError: false)
        } else if let js = input["javascript"]?.stringValue {
            overlayManager.updateOverlayPartial(javascript: js)
            return .toolResult(toolUseId: toolId, content: [.text("Overlay updated via JavaScript")], isError: false)
        } else {
            return .toolResult(toolUseId: toolId, content: [.text("Provide either 'html' or 'javascript' parameter")], isError: true)
        }
    }
}
