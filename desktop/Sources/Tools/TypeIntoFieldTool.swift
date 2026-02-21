import Foundation
import CoreGraphics

struct TypeIntoFieldTool: AgentTool {
    let name = "type_into_field"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Find an input field by searching the accessibility tree, click it to focus, then type text. \
                Searches title, description, and role description (case-insensitive partial match). \
                Use find_elements or get_input_fields first to discover available fields.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "label": ToolProperty(type: "string", description: "Text to search for in the input field's title or description", enumValues: nil),
                    "text": ToolProperty(type: "string", description: "Text to type into the field", enumValues: nil)
                ],
                required: ["label", "text"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let label = input["label"]?.stringValue, !label.isEmpty else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'label' parameter")], isError: true)
        }
        guard let text = input["text"]?.stringValue else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'text' parameter")], isError: true)
        }

        guard let tree = ActiveAppState.shared.contextTree else {
            return .toolResult(toolUseId: toolId, content: [.text("No accessibility tree available")], isError: true)
        }

        // Search full tree for matching input-like elements
        let matches = tree.search(query: label)
        let clickable = matches.filter { $0.frame != nil }

        // Prefer actual input fields, but accept any clickable match
        let inputMatches = clickable.filter { $0.isInputField }
        let element = inputMatches.first ?? clickable.first

        guard let element = element, let frame = element.frame else {
            let available = ActiveAppState.shared.inputFields.compactMap { $0.bestLabel }
            return .toolResult(toolUseId: toolId, content: [.text("No input field matching '\(label)' found. Available fields: \(available.joined(separator: ", "))")], isError: true)
        }

        let ctx = context.targetContext
        let centerX = Int((frame.origin.x - ctx.bounds.origin.x + frame.width / 2) * ctx.retinaScale)
        let centerY = Int((frame.origin.y - ctx.bounds.origin.y + frame.height / 2) * ctx.retinaScale)

        _ = await InteractionTools.click(x: centerX, y: centerY, context: ctx)
        let result = await InteractionTools.typeText(text, context: ctx)

        let fieldLabel = element.bestLabel ?? element.role
        return .toolResult(toolUseId: toolId, content: [.text("Typed into \(element.role) '\(fieldLabel)'. \(result.message)")], isError: !result.success)
    }
}
