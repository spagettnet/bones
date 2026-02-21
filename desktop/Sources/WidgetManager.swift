import AppKit

@MainActor
class WidgetManager {
    private var widgets: [String: WidgetWindow] = [:]
    private let windowTracker: WindowTracker
    private let targetContext: TargetContext
    private var lastTargetBounds: CGRect

    init(windowTracker: WindowTracker, targetContext: TargetContext) {
        self.windowTracker = windowTracker
        self.targetContext = targetContext
        self.lastTargetBounds = targetContext.bounds
    }

    func showWidget(id: String, type: String, x: Int, y: Int, title: String, config: [String: Any]) -> ToolResult {
        BoneLog.log("WidgetManager: showWidget id=\(id) type=\(type) at (\(x),\(y)) title=\(title)")

        // Dismiss existing widget with same ID
        if let existing = widgets[id] {
            existing.close()
            widgets.removeValue(forKey: id)
        }

        // Create content provider based on type
        let provider: WidgetContentProvider
        switch type {
        case "color_swatch":
            provider = ColorSwatchWidget(config: config)
        case "json_viewer":
            provider = JSONViewerWidget(config: config)
        case "code_snippet":
            provider = CodeSnippetWidget(config: config)
        case "custom_html":
            provider = CustomHTMLWidget(config: config)
        default:
            BoneLog.log("WidgetManager: unknown widget type '\(type)'")
            return ToolResult(success: false, message: "Unknown widget type: \(type). Use: color_swatch, json_viewer, code_snippet, custom_html")
        }

        let window = WidgetWindow(
            widgetId: id,
            title: title,
            contentProvider: provider,
            anchorImageX: x,
            anchorImageY: y
        )

        // Position using current target bounds
        let currentBounds = windowTracker.currentBounds()
        let screenPoint = InteractionTools.screenPoint(fromImageX: x, imageY: y, context: TargetContext(
            windowID: targetContext.windowID,
            ownerPID: targetContext.ownerPID,
            bounds: currentBounds,
            retinaScale: targetContext.retinaScale
        ))

        // Convert CG point (top-left origin) to AppKit (bottom-left origin)
        guard let screen = NSScreen.main else {
            return ToolResult(success: false, message: "No screen available")
        }
        let appKitY = screen.frame.height - screenPoint.y - window.frame.height
        window.setFrameOrigin(NSPoint(x: screenPoint.x, y: appKitY))

        widgets[id] = window
        window.makeKeyAndOrderFront(nil)

        BoneLog.log("WidgetManager: widget '\(id)' shown at screen (\(screenPoint.x), \(appKitY))")
        return ToolResult(success: true, message: "Widget '\(id)' shown at (\(x), \(y))")
    }

    func dismissWidget(id: String) -> ToolResult {
        BoneLog.log("WidgetManager: dismissWidget id=\(id)")

        if id == "all" {
            dismissAll()
            return ToolResult(success: true, message: "All widgets dismissed")
        }

        guard let window = widgets[id] else {
            return ToolResult(success: false, message: "No widget with id '\(id)'")
        }

        window.close()
        widgets.removeValue(forKey: id)
        return ToolResult(success: true, message: "Widget '\(id)' dismissed")
    }

    func targetWindowMoved(newBounds: CGRect) {
        let dx = newBounds.origin.x - lastTargetBounds.origin.x
        let dy = newBounds.origin.y - lastTargetBounds.origin.y
        lastTargetBounds = newBounds

        guard dx != 0 || dy != 0 else { return }

        for (_, window) in widgets {
            window.moveBy(dx: dx, dy: dy)
        }
    }

    func dismissAll() {
        BoneLog.log("WidgetManager: dismissAll (\(widgets.count) widgets)")
        for (_, window) in widgets {
            window.close()
        }
        widgets.removeAll()
    }
}
