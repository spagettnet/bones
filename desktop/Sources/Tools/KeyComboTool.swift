import Foundation
import CoreGraphics

struct KeyComboTool: AgentTool {
    let name = "key_combo"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Press a keyboard shortcut. Pass an array of key names: modifier keys \
                (cmd, ctrl, shift, alt/option) plus one main key (a-z, 0-9, return, tab, \
                escape, space, delete, f1-f12, left/right/up/down, etc.). \
                Examples: ["cmd","c"] for copy, ["cmd","shift","f"] for find in files, \
                ["return"] for enter, ["cmd","w"] to close tab.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "keys": ToolProperty(
                        type: "array",
                        description: "Array of key names, e.g. [\"cmd\", \"p\"] or [\"ctrl\", \"shift\", \"n\"]",
                        items: ToolPropertyItems(type: "string")
                    )
                ],
                required: ["keys"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard case .array(let keysArray) = input["keys"] else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'keys' array parameter")], isError: true)
        }

        let keys = keysArray.compactMap { $0.stringValue }
        guard !keys.isEmpty else {
            return .toolResult(toolUseId: toolId, content: [.text("'keys' array must contain at least one key name")], isError: true)
        }

        let result = await InteractionTools.keyCombo(keys: keys, context: context.targetContext)
        return .toolResult(toolUseId: toolId, content: [.text(result.message)], isError: !result.success)
    }
}
