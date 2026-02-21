import Foundation
import CoreGraphics

struct ClickElementTool: AgentTool {
    let name = "click_element"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Click a UI element by searching for it in the accessibility tree. \
                Searches title, description, role description, and role fields (case-insensitive partial match). \
                Finds the element and clicks its center — much more reliable than clicking by coordinates. \
                Use find_elements first if you're not sure of the exact label.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "label": ToolProperty(type: "string", description: "Text to search for in the element's title, description, or role description", enumValues: nil)
                ],
                required: ["label"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let label = input["label"]?.stringValue, !label.isEmpty else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'label' parameter")], isError: true)
        }

        guard let tree = ActiveAppState.shared.contextTree else {
            return .toolResult(toolUseId: toolId, content: [.text("No accessibility tree available")], isError: true)
        }

        // Search the entire tree, not just filtered buttons
        let matches = tree.search(query: label)

        // Prefer matches that have a frame (clickable)
        let clickable = matches.filter { $0.frame != nil }
        guard let element = clickable.first else {
            if !matches.isEmpty {
                let labels = matches.prefix(5).map { $0.summary }
                return .toolResult(toolUseId: toolId, content: [.text("Found \(matches.count) elements matching '\(label)' but none have a clickable frame. Matches: \(labels.joined(separator: ", "))")], isError: true)
            }
            // Suggest nearby matches
            let allButtons = ActiveAppState.shared.buttons.prefix(15).compactMap { $0.bestLabel }
            return .toolResult(toolUseId: toolId, content: [.text("No elements found matching '\(label)'. Try find_elements with a different query. Some available buttons: \(allButtons.joined(separator: ", "))")], isError: true)
        }

        let frame = element.frame!
        let ctx = context.targetContext
        let centerX = Int((frame.origin.x - ctx.bounds.origin.x + frame.width / 2) * ctx.retinaScale)
        let centerY = Int((frame.origin.y - ctx.bounds.origin.y + frame.height / 2) * ctx.retinaScale)
        let result = await InteractionTools.click(x: centerX, y: centerY, context: ctx)

        let elementLabel = element.bestLabel ?? element.role
        let matchInfo = clickable.count > 1 ? " (\(clickable.count) matches, clicked first)" : ""
        return .toolResult(toolUseId: toolId, content: [.text("Clicked \(element.role) '\(elementLabel)' at center (\(centerX), \(centerY))\(matchInfo). \(result.message)")], isError: !result.success)
    }
}
