import Foundation

struct DestroyOverlayTool: AgentTool {
    let name = "destroy_overlay"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Close and destroy the current overlay window.",
            inputSchema: ToolSchema(properties: [:], required: [])
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let overlayManager = context.overlayManager else {
            return .toolResult(toolUseId: toolId, content: [.text("Overlay system not available")], isError: true)
        }
        guard overlayManager.hasOverlay else {
            return .toolResult(toolUseId: toolId, content: [.text("No overlay is currently active")], isError: true)
        }

        overlayManager.destroyOverlay()
        return .toolResult(toolUseId: toolId, content: [.text("Overlay destroyed")], isError: false)
    }
}
