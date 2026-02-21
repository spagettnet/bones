import Foundation

struct ScrollTool: AgentTool {
    let name = "scroll"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
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
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let x = input["x"]?.intValue ?? 0
        let y = input["y"]?.intValue ?? 0
        let direction = input["direction"]?.stringValue ?? "down"
        let amount = input["amount"]?.intValue ?? 3
        let result = await InteractionTools.scroll(x: x, y: y, direction: direction, amount: amount, context: context.targetContext)
        return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)
    }
}
