import Foundation

struct ClickTool: AgentTool {
    let name = "click"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Click at a position in the target window. Coordinates are in image pixel space (2x retina).",
            inputSchema: ToolSchema(
                properties: [
                    "x": ToolProperty(type: "integer", description: "X coordinate in image pixels", enumValues: nil),
                    "y": ToolProperty(type: "integer", description: "Y coordinate in image pixels", enumValues: nil)
                ],
                required: ["x", "y"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let x = input["x"]?.intValue ?? 0
        let y = input["y"]?.intValue ?? 0
        let result = await InteractionTools.click(x: x, y: y, context: context.targetContext)
        return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)
    }
}
