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
                Uses the native accessibility API to press the element directly — no coordinate guessing needed. \
                Falls back to clicking the element's center coordinates if native press isn't supported. \
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

        let ctx = context.targetContext

        // First, try native AXPress on the live AX tree — most reliable
        if AccessibilityHelper.pressElement(query: label, pid: ctx.ownerPID, windowBounds: ctx.bounds) {
            return .toolResult(toolUseId: toolId, content: [.text("Pressed element matching '\(label)' via accessibility API (native press)")], isError: false)
        }

        // Fallback: search the snapshot tree and click by frame coordinates
        guard let tree = ActiveAppState.shared.contextTree else {
            return .toolResult(toolUseId: toolId, content: [.text("No accessibility tree available and native press failed for '\(label)'")], isError: true)
        }

        let matches = tree.search(query: label)
        let clickable = matches.filter { $0.frame != nil }

        guard let element = clickable.first, let frame = element.frame else {
            if !matches.isEmpty {
                let labels = matches.prefix(5).map { $0.summary }
                return .toolResult(toolUseId: toolId, content: [.text("Found \(matches.count) elements matching '\(label)' but couldn't press or click them. Matches: \(labels.joined(separator: ", "))")], isError: true)
            }
            let allButtons = ActiveAppState.shared.buttons.prefix(15).compactMap { $0.bestLabel }
            return .toolResult(toolUseId: toolId, content: [.text("No elements found matching '\(label)'. Try find_elements with a different query. Some available buttons: \(allButtons.joined(separator: ", "))")], isError: true)
        }

        // Click by frame center as fallback
        let centerX = Int((frame.origin.x - ctx.bounds.origin.x + frame.width / 2) * ctx.retinaScale)
        let centerY = Int((frame.origin.y - ctx.bounds.origin.y + frame.height / 2) * ctx.retinaScale)
        let result = await InteractionTools.click(x: centerX, y: centerY, context: ctx)

        let elementLabel = element.bestLabel ?? element.role
        return .toolResult(toolUseId: toolId, content: [.text("Clicked \(element.role) '\(elementLabel)' at center (\(centerX), \(centerY)) (coordinate fallback). \(result.message)")], isError: !result.success)
    }
}
