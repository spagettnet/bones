import Foundation
import AppKit

// MARK: - Delegate

@MainActor
protocol AgentBridgeDelegate: AnyObject {
    func agentBridgeDidUpdateMessages(_ bridge: AgentBridge)
    func agentBridgeDidEncounterError(_ bridge: AgentBridge, error: String)
}

// MARK: - AgentBridge

@MainActor
class AgentBridge {
    weak var delegate: AgentBridgeDelegate?
    private(set) var uiMessages: [ChatMessageUI] = []
    private(set) var isRunning = false

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readTask: Task<Void, Never>?

    private let executionContext: ToolExecutionContext
    private let overlayManager: OverlayManager?
    private let widgetManager: WidgetManager?

    init(executionContext: ToolExecutionContext, overlayManager: OverlayManager?, widgetManager: WidgetManager? = nil) {
        self.executionContext = executionContext
        self.overlayManager = overlayManager
        self.widgetManager = widgetManager
    }

    // MARK: - Lifecycle

    func start(apiKey: String) async {
        guard !isRunning else { return }

        // Capture initial screenshot + element codes
        let screenshotRaw = await ScreenshotCapture.captureToData(windowID: executionContext.windowID)
        var screenshotBase64 = ""
        var screenshotMediaType = "image/png"
        if let raw = screenshotRaw {
            let compressed = ScreenshotCapture.compressForAPI(raw)
            screenshotBase64 = compressed.data.base64EncodedString()
            screenshotMediaType = compressed.mediaType
        }
        let elementCodes = ElementLabeler.shared.codeMap()

        // Detect page URL and matching site apps (browser only)
        var pageURL = ""
        var siteApps: [[String: Any]] = []
        let appName = ActiveAppState.shared.appName
        if Self.isBrowser(appName) {
            let urlResult = await InteractionTools.runJavaScriptInBrowser(
                js: "window.location.href", appName: appName)
            if urlResult.success && !urlResult.message.isEmpty {
                pageURL = urlResult.message
                ActiveAppState.shared.pageURL = pageURL
                siteApps = SiteAppRegistry.shared.appsForURL(pageURL).map { app in
                    ["id": app.id, "name": app.name, "description": app.description] as [String: Any]
                }
                BoneLog.log("AgentBridge: page URL=\(pageURL), site apps=\(siteApps.count)")
            }
        }

        // Find the agent project directory (repo root / agent/)
        // The app bundle is at desktop/build/Bones.app — go up to repo root
        let bundle = Bundle.main
        let bundlePath = bundle.bundlePath  // .../desktop/build/Bones.app
        let desktopDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().deletingLastPathComponent()
        let agentProjectDir = desktopDir.deletingLastPathComponent().appendingPathComponent("agent")
        let agentScript = agentProjectDir.appendingPathComponent("agent.py").path

        guard FileManager.default.fileExists(atPath: agentScript) else {
            BoneLog.log("AgentBridge: agent.py not found at \(agentScript)")
            delegate?.agentBridgeDidEncounterError(self, error: "agent.py not found at \(agentScript)")
            return
        }

        // Launch via uv run for proper venv/dependency management
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", "--project", agentProjectDir.path, "python", "-u", agentScript]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        do {
            try proc.run()
        } catch {
            BoneLog.log("AgentBridge: failed to launch python: \(error)")
            delegate?.agentBridgeDidEncounterError(self, error: "Failed to launch agent: \(error.localizedDescription)")
            return
        }

        isRunning = true
        BoneLog.log("AgentBridge: python process launched (pid \(proc.processIdentifier))")

        // Add initial UI message
        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .user,
            text: "[Screenshot sent] What do you see?",
            isStreaming: false
        ))
        delegate?.agentBridgeDidUpdateMessages(self)

        // Start reading stdout
        startReading()

        // Start reading stderr for logging
        startStderrReading()

        // Send init message
        var initMsg: [String: Any] = [
            "type": "init",
            "api_key": apiKey,
            "screenshot_base64": screenshotBase64,
            "screenshot_media_type": screenshotMediaType,
            "element_codes": elementCodes
        ]
        if !pageURL.isEmpty {
            initMsg["page_url"] = pageURL
        }
        if !siteApps.isEmpty {
            initMsg["site_apps"] = siteApps
        }
        let savedOverlays = SavedOverlayStore.shared.list()
        if !savedOverlays.isEmpty {
            initMsg["saved_overlays"] = savedOverlays.map { overlay in
                [
                    "id": overlay.id,
                    "name": overlay.name,
                    "description": overlay.description
                ] as [String: Any]
            }
        }
        sendToProcess(initMsg)
    }

    func sendUserMessage(text: String) {
        guard isRunning else { return }

        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .user, text: text, isStreaming: false
        ))
        delegate?.agentBridgeDidUpdateMessages(self)

        sendToProcess(["type": "user_message", "text": text])
    }

    func stop() {
        guard isRunning else { return }
        BoneLog.log("AgentBridge: stopping")

        // Try to send cancel first
        sendToProcess(["type": "cancel"])

        isRunning = false
        readTask?.cancel()
        readTask = nil

        // Terminate process after a brief grace period
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        // Mark streaming messages as done
        for i in uiMessages.indices {
            if uiMessages[i].isStreaming {
                uiMessages[i].isStreaming = false
            }
        }
        uiMessages.append(ChatMessageUI(
            id: UUID(), role: .assistant, text: "[Stopped]", isStreaming: false
        ))
        delegate?.agentBridgeDidUpdateMessages(self)
    }

    var isCurrentlyProcessing: Bool { isRunning }

    func cancelProcessing() {
        stop()
    }

    // MARK: - IPC

    private func sendToProcess(_ msg: [String: Any]) {
        guard let pipe = stdinPipe else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        pipe.fileHandleForWriting.write(Data(line.utf8))
    }

    private func startReading() {
        guard let pipe = stdoutPipe else { return }
        let fileHandle = pipe.fileHandleForReading

        readTask = Task.detached { [weak self] in
            var leftover = ""

            while !Task.isCancelled {
                let data = fileHandle.availableData
                if data.isEmpty {
                    // EOF — process exited
                    break
                }
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                let combined = leftover + chunk
                let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)

                // All lines except the last are complete
                for i in 0..<(lines.count - 1) {
                    let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    if let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                        await MainActor.run { [weak self] in
                            self?.handleMessage(json)
                        }
                    }
                }
                // Last element is either empty (line ended with \n) or partial
                leftover = String(lines.last ?? "")
            }

            // Process any remaining data
            if !leftover.isEmpty {
                let line = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                    await MainActor.run { [weak self] in
                        self?.handleMessage(json)
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if self.isRunning {
                    BoneLog.log("AgentBridge: python process exited")
                    self.isRunning = false
                }
            }
        }
    }

    private func startStderrReading() {
        guard let pipe = stderrPipe else { return }
        let fileHandle = pipe.fileHandleForReading

        Task.detached {
            var leftover = ""
            while true {
                let data = fileHandle.availableData
                if data.isEmpty { break }
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                let combined = leftover + chunk
                let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
                for i in 0..<(lines.count - 1) {
                    let line = String(lines[i])
                    BoneLog.log("Agent: \(line)")
                }
                leftover = String(lines.last ?? "")
            }
            if !leftover.isEmpty {
                BoneLog.log("Agent: \(leftover)")
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }

        switch type {
        case "streaming_start":
            // Add streaming placeholder
            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant, text: "", isStreaming: true
            ))
            delegate?.agentBridgeDidUpdateMessages(self)

        case "text_delta":
            if let text = msg["text"] as? String, let lastIdx = lastStreamingIndex() {
                uiMessages[lastIdx].text += text
                delegate?.agentBridgeDidUpdateMessages(self)
            }

        case "streaming_end":
            if let lastIdx = lastStreamingIndex() {
                uiMessages[lastIdx].isStreaming = false
                delegate?.agentBridgeDidUpdateMessages(self)
            }

        case "assistant_message":
            // Full text already streamed — no additional UI action needed
            break

        case "tool_use":
            let toolName = msg["name"] as? String ?? "unknown"
            let toolId = msg["id"] as? String ?? ""
            let toolInput = msg["input"] as? [String: Any] ?? [:]

            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant,
                text: "Using \(toolName)...",
                isStreaming: false
            ))
            delegate?.agentBridgeDidUpdateMessages(self)

            // Execute tool natively and send result back
            Task {
                let result = await self.executeNativeTool(name: toolName, id: toolId, input: toolInput)
                self.sendToProcess(result)
            }

        case "done":
            BoneLog.log("AgentBridge: turn complete")

        case "error":
            let message = msg["message"] as? String ?? "Unknown error"
            BoneLog.log("AgentBridge: error from agent: \(message)")
            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant,
                text: "Error: \(message)",
                isStreaming: false
            ))
            delegate?.agentBridgeDidUpdateMessages(self)

        default:
            BoneLog.log("AgentBridge: unknown message type: \(type)")
        }
    }

    private func lastStreamingIndex() -> Int? {
        uiMessages.indices.last { uiMessages[$0].isStreaming }
    }

    // MARK: - Native Tool Execution

    private func executeNativeTool(name: String, id: String, input: [String: Any]) async -> [String: Any] {
        let ctx = executionContext.targetContext

        switch name {
        case "take_screenshot":
            return await executeTakeScreenshot(id: id, input: input)

        case "click_code":
            return await executeClickCode(id: id, input: input, context: ctx)

        case "type_into_code":
            return await executeTypeIntoCode(id: id, input: input, context: ctx)

        case "click":
            let x = input["x"] as? Int ?? 0
            let y = input["y"] as? Int ?? 0
            let result = await InteractionTools.click(x: x, y: y, context: ctx)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "type_text":
            let text = input["text"] as? String ?? ""
            let result = await InteractionTools.typeText(text, context: ctx)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "scroll":
            let x = input["x"] as? Int ?? 0
            let y = input["y"] as? Int ?? 0
            let direction = input["direction"] as? String ?? "down"
            let amount = input["amount"] as? Int ?? 3
            let result = await InteractionTools.scroll(x: x, y: y, direction: direction, amount: amount, context: ctx)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "key_combo":
            let keys = input["keys"] as? [String] ?? []
            let result = await InteractionTools.keyCombo(keys: keys, context: ctx)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "get_elements":
            let codes = ElementLabeler.shared.codeMap()
            if codes.isEmpty {
                return toolResult(id: id, text: "No labeled elements available. The accessibility tree may be empty.", isError: false)
            }
            let lines = codes.map { e -> String in
                let code = e["code"] as? String ?? "?"
                let type = e["type"] as? String ?? "?"
                let label = e["label"] as? String ?? e["role"] as? String ?? "?"
                return "[\(code)] \(type): \"\(label)\""
            }
            return toolResult(id: id, text: lines.joined(separator: "\n"), isError: false)

        case "find_elements":
            let query = input["query"] as? String ?? ""
            guard let tree = ActiveAppState.shared.contextTree else {
                return toolResult(id: id, text: "No accessibility tree available", isError: true)
            }
            let matches = tree.search(query: query)
            if matches.isEmpty {
                return toolResult(id: id, text: "No elements found matching '\(query)'", isError: false)
            }
            let lines = matches.prefix(20).map { node -> String in
                let label = node.bestLabel ?? node.role
                var desc = "\(node.role): \"\(label)\""
                if let f = node.frame {
                    desc += " at (\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)))"
                }
                return desc
            }
            return toolResult(id: id, text: "Found \(matches.count) elements:\n" + lines.joined(separator: "\n"), isError: false)

        case "create_overlay":
            let html = input["html"] as? String ?? ""
            let width = CGFloat(input["width"] as? Int ?? 400)
            let height = CGFloat(input["height"] as? Int ?? 300)
            let position = input["position"] as? String
            overlayManager?.createOverlay(html: html, width: width, height: height, position: position)
            return toolResult(id: id, text: "Overlay created (\(Int(width))x\(Int(height)))", isError: false)

        case "update_overlay":
            if let html = input["html"] as? String {
                overlayManager?.updateOverlay(html: html)
                return toolResult(id: id, text: "Overlay updated with new HTML", isError: false)
            } else if let js = input["javascript"] as? String {
                overlayManager?.updateOverlayPartial(javascript: js)
                return toolResult(id: id, text: "Executed JavaScript in overlay", isError: false)
            }
            return toolResult(id: id, text: "Provide 'html' or 'javascript' parameter", isError: true)

        case "destroy_overlay":
            overlayManager?.destroyOverlay()
            return toolResult(id: id, text: "Overlay destroyed", isError: false)

        case "get_overlay_logs":
            guard let om = overlayManager else {
                return toolResult(id: id, text: "No overlay manager", isError: true)
            }
            let logs = om.overlayLogs
            if logs.isEmpty {
                return toolResult(id: id, text: "(no overlay logs)", isError: false)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let lines = logs.map { entry in
                "[\(formatter.string(from: entry.timestamp))] \(entry.level.uppercased()): \(entry.message)"
            }
            return toolResult(id: id, text: lines.joined(separator: "\n"), isError: false)

        case "show_widget":
            guard let wm = widgetManager else {
                return toolResult(id: id, text: "Widget manager not available", isError: true)
            }
            let widgetId = input["widget_id"] as? String ?? "widget-\(UUID().uuidString.prefix(8))"
            let type = input["type"] as? String ?? "custom_html"
            let x = input["x"] as? Int ?? 0
            let y = input["y"] as? Int ?? 0
            let title = input["title"] as? String ?? "Widget"
            let config = input["config"] as? [String: Any] ?? [:]
            let result = wm.showWidget(id: widgetId, type: type, x: x, y: y, title: title, config: config)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "dismiss_widget":
            guard let wm = widgetManager else {
                return toolResult(id: id, text: "Widget manager not available", isError: true)
            }
            let widgetId = input["widget_id"] as? String ?? "all"
            let result = wm.dismissWidget(id: widgetId)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "read_editor_content":
            let textResults = AccessibilityHelper.readTextContent(pid: ctx.ownerPID, bounds: ctx.bounds)
            if textResults.isEmpty {
                return toolResult(id: id, text: "No text area found in the target window.", isError: false)
            }
            var output = ""
            for (i, r) in textResults.enumerated() {
                if textResults.count > 1 {
                    let titleStr = r.title.map { ": \($0)" } ?? ""
                    output += "--- Text Area \(i + 1) (\(r.role)\(titleStr)) ---\n"
                }
                output += r.text
                if r.wasTruncated {
                    output += "\n\n[Truncated — total \(r.characterCount) characters]"
                }
                output += "\n"
            }
            return toolResult(id: id, text: output, isError: false)

        case "run_javascript":
            let js = input["javascript"] as? String ?? ""
            guard !js.isEmpty else {
                return toolResult(id: id, text: "javascript parameter is required", isError: true)
            }
            let appName = ActiveAppState.shared.appName
            let result = await InteractionTools.runJavaScriptInBrowser(js: js, appName: appName)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "visualize":
            let html = input["html"] as? String ?? ""
            let vizTitle = input["title"] as? String
            guard !html.isEmpty else {
                return toolResult(id: id, text: "html parameter is required", isError: true)
            }
            uiMessages.append(ChatMessageUI(
                id: UUID(), role: .assistant,
                text: "",
                isStreaming: false,
                visualizationHTML: html,
                visualizationTitle: vizTitle
            ))
            delegate?.agentBridgeDidUpdateMessages(self)
            let titleNote = vizTitle.map { ": \($0)" } ?? ""
            return toolResult(id: id, text: "Visualization rendered in sidebar\(titleNote)", isError: false)

        case "launch_site_app":
            let appId = input["app_id"] as? String ?? ""
            let pageURL = input["url"] as? String ?? ""
            let result = await SiteAppRegistry.shared.launch(appId: appId, pageURL: pageURL)
            return toolResult(id: id, text: result.message, isError: !result.success)

        case "save_overlay":
            guard let overlayId = input["id"] as? String, !overlayId.isEmpty else {
                return toolResult(id: id, text: "Missing 'id' parameter", isError: true)
            }
            guard let html = input["html"] as? String, !html.isEmpty else {
                return toolResult(id: id, text: "Missing 'html' parameter", isError: true)
            }
            let overlayName = input["name"] as? String ?? overlayId
            let desc = input["description"] as? String ?? ""
            let width = input["width"] as? Int ?? 400
            let height = input["height"] as? Int ?? 300
            let position = input["position"] as? String
            let saveResult = SavedOverlayStore.shared.save(
                id: overlayId, name: overlayName, description: desc,
                html: html, width: width, height: height, position: position)
            if saveResult.success {
                overlayManager?.createOverlay(
                    html: html, width: CGFloat(width), height: CGFloat(height), position: position)
            }
            return toolResult(id: id, text: saveResult.message, isError: !saveResult.success)

        case "read_overlay_source":
            guard let overlayId = input["id"] as? String, !overlayId.isEmpty else {
                return toolResult(id: id, text: "Missing 'id' parameter", isError: true)
            }
            guard let overlay = SavedOverlayStore.shared.load(id: overlayId) else {
                return toolResult(id: id, text: "No saved overlay with id '\(overlayId)' found", isError: true)
            }
            return toolResult(id: id, text: overlay.html, isError: false)

        case "list_saved_overlays":
            let overlays = SavedOverlayStore.shared.list()
            if overlays.isEmpty {
                return toolResult(id: id, text: "No saved overlays for this app/site.", isError: false)
            }
            let lines = overlays.map { o in
                "- \(o.name) (id: \(o.id)): \(o.description)"
            }
            return toolResult(id: id, text: "Saved overlays:\n" + lines.joined(separator: "\n"), isError: false)

        case "load_overlay":
            guard let overlayId = input["id"] as? String, !overlayId.isEmpty else {
                return toolResult(id: id, text: "Missing 'id' parameter", isError: true)
            }
            guard let overlay = SavedOverlayStore.shared.load(id: overlayId) else {
                return toolResult(id: id, text: "No saved overlay with id '\(overlayId)' found", isError: true)
            }
            overlayManager?.createOverlay(
                html: overlay.html,
                width: CGFloat(overlay.width),
                height: CGFloat(overlay.height),
                position: overlay.position)
            return toolResult(id: id, text: "Loaded overlay '\(overlay.name)' (\(overlay.width)x\(overlay.height))", isError: false)

        default:
            return toolResult(id: id, text: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - Helpers

    static func isBrowser(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("chrome") || lower.contains("safari") || lower.contains("arc")
            || lower.contains("brave") || lower.contains("edge") || lower.contains("firefox")
            || lower.contains("vivaldi") || lower.contains("opera")
    }

    // MARK: - Tool Implementations

    private func executeTakeScreenshot(id: String, input: [String: Any]) async -> [String: Any] {
        let target = input["target"] as? String ?? "app"
        let labeled = input["labeled"] as? Bool ?? false

        var imageData: Data?

        switch target {
        case "overlay":
            if let om = overlayManager, om.hasOverlay, let wid = om.overlayWindowID {
                imageData = await ScreenshotCapture.captureToData(windowID: wid)
            } else {
                return toolResult(id: id, text: "No overlay active", isError: true)
            }
        case "both":
            let appBounds = executionContext.targetContext.bounds
            var captureRect = appBounds
            if let om = overlayManager, om.hasOverlay, let overlayFrame = om.overlayFrame {
                captureRect = captureRect.union(overlayFrame)
            }
            imageData = await ScreenshotCapture.captureRegionToData(rect: captureRect)
        default: // "app"
            imageData = await ScreenshotCapture.captureToData(windowID: executionContext.windowID)
        }

        guard let data = imageData else {
            return toolResult(id: id, text: "Screenshot failed", isError: true)
        }

        if labeled {
            let bounds = executionContext.targetContext.bounds
            let scale = executionContext.retinaScale
            if let annotated = ScreenshotCapture.annotateWithCodes(imageData: data, windowBounds: bounds, retinaScale: scale) {
                let compressed = ScreenshotCapture.compressForAPI(annotated.data)
                return toolResultWithImage(id: id, imageBase64: compressed.data.base64EncodedString(), mediaType: compressed.mediaType, text: "Element legend:\n\(annotated.legend)")
            }
        }

        let compressed = ScreenshotCapture.compressForAPI(data)
        return toolResultWithImage(id: id, imageBase64: compressed.data.base64EncodedString(), mediaType: compressed.mediaType)
    }

    private func executeClickCode(id: String, input: [String: Any], context: TargetContext) async -> [String: Any] {
        guard let code = input["code"] as? String else {
            return toolResult(id: id, text: "Missing 'code' parameter", isError: true)
        }
        guard let elem = ElementLabeler.shared.element(forCode: code) else {
            return toolResult(id: id, text: "No element with code '\(code)'. Use get_elements or take_screenshot(labeled=true) to see available codes.", isError: true)
        }

        // Try native AXPress first
        let label = elem.node.bestLabel ?? ""
        if !label.isEmpty && AccessibilityHelper.pressElement(query: label, pid: context.ownerPID, windowBounds: context.bounds) {
            return toolResult(id: id, text: "Pressed [\(code)] \(elem.node.role) '\(label)' via accessibility API", isError: false)
        }

        // Fallback: click center of element frame
        let frame = elem.screenFrame
        let centerX = Int((frame.origin.x - context.bounds.origin.x + frame.width / 2) * context.retinaScale)
        let centerY = Int((frame.origin.y - context.bounds.origin.y + frame.height / 2) * context.retinaScale)
        let result = await InteractionTools.click(x: centerX, y: centerY, context: context)
        return toolResult(id: id, text: "Clicked [\(code)] \(elem.node.role) '\(label)' at center (\(centerX), \(centerY)). \(result.message)", isError: !result.success)
    }

    private func executeTypeIntoCode(id: String, input: [String: Any], context: TargetContext) async -> [String: Any] {
        guard let code = input["code"] as? String else {
            return toolResult(id: id, text: "Missing 'code' parameter", isError: true)
        }
        guard let text = input["text"] as? String else {
            return toolResult(id: id, text: "Missing 'text' parameter", isError: true)
        }
        guard let elem = ElementLabeler.shared.element(forCode: code) else {
            return toolResult(id: id, text: "No element with code '\(code)'", isError: true)
        }

        // Try native focus + set value
        let label = elem.node.bestLabel ?? ""
        if !label.isEmpty && AccessibilityHelper.focusAndSetValue(query: label, value: text, pid: context.ownerPID, windowBounds: context.bounds) {
            return toolResult(id: id, text: "Typed into [\(code)] '\(label)' via accessibility API", isError: false)
        }

        // Fallback: click + type
        let frame = elem.screenFrame
        let centerX = Int((frame.origin.x - context.bounds.origin.x + frame.width / 2) * context.retinaScale)
        let centerY = Int((frame.origin.y - context.bounds.origin.y + frame.height / 2) * context.retinaScale)
        _ = await InteractionTools.click(x: centerX, y: centerY, context: context)
        let result = await InteractionTools.typeText(text, context: context)
        return toolResult(id: id, text: "Clicked [\(code)] then typed \(text.count) chars. \(result.message)", isError: !result.success)
    }

    // MARK: - Result Helpers

    private func toolResult(id: String, text: String, isError: Bool = false) -> [String: Any] {
        return [
            "type": "tool_result",
            "id": id,
            "result": [
                "text": text,
                "is_error": isError
            ] as [String: Any]
        ]
    }

    private func toolResultWithImage(id: String, imageBase64: String, mediaType: String = "image/png", text: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["image_base64": imageBase64, "media_type": mediaType]
        if let text = text {
            result["text"] = text
        }
        return [
            "type": "tool_result",
            "id": id,
            "result": result
        ]
    }
}
