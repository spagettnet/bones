import Foundation

struct CreateOverlayTool: AgentTool {
    let name = "create_overlay"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Create a dynamic UI overlay window with custom HTML/CSS/JS. The overlay floats above \
                all windows and can interact with the target app via the window.bones bridge API. \
                Available bridge APIs (all return Promises): \
                window.bones.click(x, y) - click at image-pixel coordinates; \
                window.bones.typeText(text) - type text at cursor; \
                window.bones.scroll(x, y, direction, amount) - scroll at position; \
                window.bones.takeScreenshot() - returns {image: "data:image/png;base64,..."}; \
                window.bones.getTree() - full accessibility tree as nested JSON; \
                window.bones.getButtons() - array of {role, label, frame: {x,y,w,h}}; \
                window.bones.getInputFields() - array of {role, label, value, frame: {x,y,w,h}}; \
                window.bones.getElements() - all interactable elements; \
                window.bones.clickElement(label) - find and click element by accessibility label; \
                window.bones.typeIntoField(label, text) - find input by label, click it, type text.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "html": ToolProperty(type: "string", description: "HTML content for the overlay (can include inline CSS and JS)", enumValues: nil),
                    "width": ToolProperty(type: "integer", description: "Overlay width in pixels (default 400)", enumValues: nil),
                    "height": ToolProperty(type: "integer", description: "Overlay height in pixels (default 300)", enumValues: nil),
                    "position": ToolProperty(type: "string", description: "Overlay position", enumValues: ["top-left", "top-right", "center", "bottom-left"])
                ],
                required: ["html"]
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let overlayManager = context.overlayManager else {
            return .toolResult(toolUseId: toolId, content: [.text("Overlay system not available")], isError: true)
        }
        guard let html = input["html"]?.stringValue else {
            return .toolResult(toolUseId: toolId, content: [.text("Missing required 'html' parameter")], isError: true)
        }

        let width = CGFloat(input["width"]?.intValue ?? 400)
        let height = CGFloat(input["height"]?.intValue ?? 300)
        let position = input["position"]?.stringValue

        overlayManager.createOverlay(html: html, width: width, height: height, position: position)
        return .toolResult(
            toolUseId: toolId,
            content: [.text("Overlay created (\(Int(width))x\(Int(height))). The overlay has access to window.bones.* bridge APIs for interacting with the target app.")],
            isError: false
        )
    }
}
