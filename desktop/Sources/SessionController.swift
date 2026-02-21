import AppKit
import CoreGraphics

@MainActor
class SessionController {
    private var sidebarWindow: SidebarWindow?
    private var chatController: ChatController?
    private var windowTracker: WindowTracker?
    private var overlayManager: OverlayManager?

    func startSession(windowInfo: WindowInfo) async {
        endSession()

        // Get API key
        guard let apiKey = KeychainHelper.requireAPIKey() else { return }

        // Check accessibility permission (needed for click/type/scroll)
        if !InteractionTools.checkAccessibilityPermission() {
            InteractionTools.requestAccessibilityPermission()
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Bones needs Accessibility permission to interact with windows (click, type, scroll). Grant permission in System Settings > Privacy & Security > Accessibility, then try again."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        // Bring target window to front
        if let app = NSRunningApplication(processIdentifier: windowInfo.ownerPID) {
            app.activate()
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Re-fetch bounds (may have changed after activation)
        let bounds = freshWindowBounds(windowID: windowInfo.windowID) ?? windowInfo.bounds

        // Create window tracker
        let tracker = WindowTracker(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            initialBounds: bounds
        )
        self.windowTracker = tracker

        // Create overlay manager
        let overlay = OverlayManager()
        self.overlayManager = overlay

        // Create tool registry with all tools
        let registry = ToolRegistry()
        registry.register(ScreenshotTool())
        registry.register(ClickTool())
        registry.register(TypeTextTool())
        registry.register(ScrollTool())
        registry.register(FindElementsTool())
        registry.register(GetAccessibilityTreeTool())
        registry.register(GetButtonsTool())
        registry.register(GetInputFieldsTool())
        registry.register(ClickElementTool())
        registry.register(TypeIntoFieldTool())
        registry.register(CreateOverlayTool())
        registry.register(UpdateOverlayTool())
        registry.register(DestroyOverlayTool())

        // Build execution context
        let execContext = ToolExecutionContext(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            bounds: bounds,
            retinaScale: 2.0,
            windowTracker: tracker,
            overlayManager: overlay
        )

        // Wire overlay bridge handler
        overlay.onBridgeAction = { [weak self] action, payload, callbackId in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleBridgeAction(action: action, payload: payload, callbackId: callbackId, context: execContext)
            }
        }

        // Create chat controller
        let controller = ChatController(
            apiKey: apiKey,
            executionContext: execContext,
            toolRegistry: registry
        )
        controller.systemPrompt += """

            \nYou also have overlay tools. You can create dynamic HTML/CSS/JS UI overlays that float \
            above the target window. Overlays have access to window.bones.* APIs that can interact \
            with the target app — including taking screenshots, clicking, typing, and reading the \
            accessibility tree. Use create_overlay to build interactive tools, dashboards, or controls. \
            Use update_overlay to modify them, and destroy_overlay to remove them. \
            Use take_screenshot with target="overlay" to see your overlay, or target="both" to see \
            the app and overlay together.
            """
        self.chatController = controller

        let sidebar = SidebarWindow(
            chatController: controller,
            windowTracker: tracker,
            targetBounds: bounds
        )
        self.sidebarWindow = sidebar

        sidebar.makeKeyAndOrderFront(nil)

        await controller.startWithScreenshot()
    }

    func endSession() {
        overlayManager?.destroyOverlay()
        overlayManager = nil
        sidebarWindow?.close()
        sidebarWindow = nil
        windowTracker?.stopTracking()
        windowTracker = nil
        chatController = nil
    }

    func toggleDebugTab() {
        sidebarWindow?.toggleDebugTab()
    }

    // MARK: - Bridge Action Handler

    private func handleBridgeAction(action: String, payload: [String: Any], callbackId: String, context: ToolExecutionContext) async {
        guard let overlay = overlayManager else { return }

        switch action {
        case "click":
            let x = payload["x"] as? Int ?? 0
            let y = payload["y"] as? Int ?? 0
            let result = await InteractionTools.click(x: x, y: y, context: context.targetContext)
            overlay.sendBridgeResponse(callbackId: callbackId, result: ["success": result.success, "message": result.message])

        case "type_text":
            let text = payload["text"] as? String ?? ""
            let result = await InteractionTools.typeText(text, context: context.targetContext)
            overlay.sendBridgeResponse(callbackId: callbackId, result: ["success": result.success, "message": result.message])

        case "scroll":
            let x = payload["x"] as? Int ?? 0
            let y = payload["y"] as? Int ?? 0
            let direction = payload["direction"] as? String ?? "down"
            let amount = payload["amount"] as? Int ?? 3
            let result = await InteractionTools.scroll(x: x, y: y, direction: direction, amount: amount, context: context.targetContext)
            overlay.sendBridgeResponse(callbackId: callbackId, result: ["success": result.success, "message": result.message])

        case "take_screenshot":
            if let imageData = await ScreenshotCapture.captureToData(windowID: context.windowID) {
                let base64 = imageData.base64EncodedString()
                overlay.sendBridgeResponse(callbackId: callbackId, result: ["image": "data:image/png;base64,\(base64)"])
            } else {
                overlay.sendBridgeError(callbackId: callbackId, error: "Screenshot failed")
            }

        case "get_tree":
            if let tree = ActiveAppState.shared.contextTree {
                let json = tree.toJSON()
                overlay.sendBridgeResponse(callbackId: callbackId, result: json)
            } else {
                overlay.sendBridgeResponse(callbackId: callbackId, result: [:] as [String: Any])
            }

        case "get_buttons":
            let buttons = ActiveAppState.shared.buttons.map { node -> [String: Any] in
                var item: [String: Any] = ["role": node.role]
                item["label"] = node.title ?? node.description ?? node.roleDescription
                if let f = node.frame {
                    item["frame"] = ["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height]
                }
                return item
            }
            overlay.sendBridgeResponse(callbackId: callbackId, result: buttons)

        case "get_input_fields":
            let inputs = ActiveAppState.shared.inputFields.map { node -> [String: Any] in
                var item: [String: Any] = ["role": node.role]
                item["label"] = node.title ?? node.description ?? node.roleDescription
                item["value"] = node.value
                if let f = node.frame {
                    item["frame"] = ["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height]
                }
                return item
            }
            overlay.sendBridgeResponse(callbackId: callbackId, result: inputs)

        case "get_elements":
            let buttons = ActiveAppState.shared.buttons.map { node -> [String: Any] in
                var item: [String: Any] = ["role": node.role, "type": "button"]
                item["label"] = node.title ?? node.description ?? node.roleDescription
                if let f = node.frame {
                    item["frame"] = ["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height]
                }
                return item
            }
            let inputs = ActiveAppState.shared.inputFields.map { node -> [String: Any] in
                var item: [String: Any] = ["role": node.role, "type": "input"]
                item["label"] = node.title ?? node.description ?? node.roleDescription
                item["value"] = node.value
                if let f = node.frame {
                    item["frame"] = ["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height]
                }
                return item
            }
            overlay.sendBridgeResponse(callbackId: callbackId, result: buttons + inputs)

        case "click_element":
            let label = payload["label"] as? String ?? ""
            if let element = findElementByLabel(label, in: ActiveAppState.shared.buttons),
               let frame = element.frame {
                // Click center of element using screen coordinates (not image pixels)
                // InteractionTools expects image-pixel coords, so multiply by retina scale
                let centerX = Int((frame.origin.x - context.bounds.origin.x) * context.retinaScale + frame.width * context.retinaScale / 2)
                let centerY = Int((frame.origin.y - context.bounds.origin.y) * context.retinaScale + frame.height * context.retinaScale / 2)
                let result = await InteractionTools.click(x: centerX, y: centerY, context: context.targetContext)
                overlay.sendBridgeResponse(callbackId: callbackId, result: ["success": result.success, "message": result.message])
            } else {
                overlay.sendBridgeError(callbackId: callbackId, error: "Element with label '\(label)' not found")
            }

        case "type_into_field":
            let label = payload["label"] as? String ?? ""
            let text = payload["text"] as? String ?? ""
            if let element = findElementByLabel(label, in: ActiveAppState.shared.inputFields),
               let frame = element.frame {
                let centerX = Int((frame.origin.x - context.bounds.origin.x) * context.retinaScale + frame.width * context.retinaScale / 2)
                let centerY = Int((frame.origin.y - context.bounds.origin.y) * context.retinaScale + frame.height * context.retinaScale / 2)
                // Click the field first, then type
                _ = await InteractionTools.click(x: centerX, y: centerY, context: context.targetContext)
                let result = await InteractionTools.typeText(text, context: context.targetContext)
                overlay.sendBridgeResponse(callbackId: callbackId, result: ["success": result.success, "message": result.message])
            } else {
                overlay.sendBridgeError(callbackId: callbackId, error: "Input field with label '\(label)' not found")
            }

        default:
            overlay.sendBridgeError(callbackId: callbackId, error: "Unknown bridge action: \(action)")
        }
    }

    private func findElementByLabel(_ label: String, in elements: [AXElementNode]) -> AXElementNode? {
        let lowered = label.lowercased()
        return elements.first { node in
            let nodeLabel = node.title ?? node.description ?? node.roleDescription ?? ""
            return nodeLabel.lowercased() == lowered || nodeLabel.lowercased().contains(lowered)
        }
    }

    private func freshWindowBounds(windowID: CGWindowID) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], windowID
        ) as? [[String: Any]],
        let info = windowList.first,
        let boundsRef = info[kCGWindowBounds as String]
        else { return nil }

        var bounds = CGRect.zero
        let cfDict = boundsRef as CFTypeRef as! CFDictionary
        guard CGRectMakeWithDictionaryRepresentation(cfDict, &bounds) else { return nil }
        return bounds
    }
}
