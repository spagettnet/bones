import Foundation
import CoreGraphics

struct ScreenshotTool: AgentTool {
    let name = "take_screenshot"

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
                Take a screenshot. Use 'target' to choose what to capture: \
                "app" (default) captures only the target application window, \
                "overlay" captures only your generated overlay window, \
                "both" captures the screen region containing both the app and overlay. \
                Set 'labeled' to true to annotate the screenshot with numbered badges on all \
                interactive elements (buttons, inputs) — a legend mapping numbers to accessibility \
                labels is included in the response. Use labeled screenshots to learn the app's UI \
                layout and map visual elements to their accessibility labels for precise interaction.
                """,
            inputSchema: ToolSchema(
                properties: [
                    "target": ToolProperty(type: "string", description: "What to capture", enumValues: ["app", "overlay", "both"]),
                    "labeled": ToolProperty(type: "boolean", description: "If true, annotate interactive elements with numbered labels and return a legend", enumValues: nil)
                ],
                required: []
            )
        )
    }

    func execute(input: [String: JSONValue], toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        let target = input["target"]?.stringValue ?? "app"
        let labeled = input["labeled"]?.boolValue ?? false

        switch target {
        case "overlay":
            return await captureOverlay(toolId: toolId, context: context)
        case "both":
            return await captureBoth(toolId: toolId, context: context, labeled: labeled)
        default: // "app"
            return await captureApp(toolId: toolId, context: context, labeled: labeled)
        }
    }

    private func captureApp(toolId: String, context: ToolExecutionContext, labeled: Bool) async -> ContentBlock {
        guard let imageData = await ScreenshotCapture.captureToData(windowID: context.windowID) else {
            return .toolResult(toolUseId: toolId, content: [.text("Screenshot failed")], isError: true)
        }

        if labeled {
            return annotateAndReturn(imageData: imageData, toolId: toolId, context: context)
        }

        let base64 = imageData.base64EncodedString()
        return .toolResult(
            toolUseId: toolId,
            content: [.image(mediaType: "image/png", base64Data: base64)],
            isError: false
        )
    }

    private func captureOverlay(toolId: String, context: ToolExecutionContext) async -> ContentBlock {
        guard let overlayManager = context.overlayManager, overlayManager.hasOverlay else {
            return .toolResult(toolUseId: toolId, content: [.text("No overlay is currently active")], isError: true)
        }
        guard let overlayWID = overlayManager.overlayWindowID else {
            return .toolResult(toolUseId: toolId, content: [.text("Could not identify overlay window")], isError: true)
        }

        guard let imageData = await ScreenshotCapture.captureToData(windowID: overlayWID) else {
            return .toolResult(toolUseId: toolId, content: [.text("Overlay screenshot failed")], isError: true)
        }

        let base64 = imageData.base64EncodedString()
        return .toolResult(
            toolUseId: toolId,
            content: [.image(mediaType: "image/png", base64Data: base64)],
            isError: false
        )
    }

    private func captureBoth(toolId: String, context: ToolExecutionContext, labeled: Bool) async -> ContentBlock {
        let appBounds = context.targetContext.bounds

        // Union of app bounds and overlay bounds
        var captureRect = appBounds
        if let overlayManager = context.overlayManager, overlayManager.hasOverlay,
           let overlayFrame = overlayManager.overlayFrame {
            captureRect = captureRect.union(overlayFrame)
        }

        guard let imageData = await ScreenshotCapture.captureRegionToData(rect: captureRect) else {
            return .toolResult(toolUseId: toolId, content: [.text("Screenshot failed")], isError: true)
        }

        if labeled {
            return annotateAndReturn(imageData: imageData, toolId: toolId, context: context, overrideBounds: captureRect)
        }

        let base64 = imageData.base64EncodedString()
        return .toolResult(
            toolUseId: toolId,
            content: [.image(mediaType: "image/png", base64Data: base64)],
            isError: false
        )
    }

    private func annotateAndReturn(imageData: Data, toolId: String, context: ToolExecutionContext, overrideBounds: CGRect? = nil) -> ContentBlock {
        let elements = ActiveAppState.shared.buttons + ActiveAppState.shared.inputFields
        let bounds = overrideBounds ?? context.targetContext.bounds
        let scale = context.retinaScale

        guard let result = ScreenshotCapture.annotateWithLabels(
            imageData: imageData, elements: elements, windowBounds: bounds, retinaScale: scale
        ) else {
            // Fallback: return unannotated screenshot
            let base64 = imageData.base64EncodedString()
            return .toolResult(
                toolUseId: toolId,
                content: [.image(mediaType: "image/png", base64Data: base64), .text("(annotation failed, showing raw screenshot)")],
                isError: false
            )
        }

        let base64 = result.data.base64EncodedString()
        return .toolResult(
            toolUseId: toolId,
            content: [
                .image(mediaType: "image/png", base64Data: base64),
                .text("Element legend:\n\(result.legend)")
            ],
            isError: false
        )
    }
}
