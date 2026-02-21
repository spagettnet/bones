import Foundation

struct TypeTextTool: AgentTool {
    let name = "type_text"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Type text at the current cursor position in the target window.",
            inputSchema: ToolSchema(
                properties: [
                    "text": ToolProperty(type: "string", description: "Text to type", enumValues: nil)
                ],
                required: ["text"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let text = input["text"]?.stringValue ?? ""
        let result = await InteractionTools.typeText(text, context: context.targetContext)
        return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)
    }
}
