import AppKit
import WebKit

@MainActor
class SidebarWindow: NSPanel, ChatControllerDelegate {
    private let sidebarWidth: CGFloat = 340
    private let chatController: ChatController
    private let windowTracker: WindowTracker
    private var tabControl: NSSegmentedControl!
    private var chatContainer: NSView!
    private var debugView: SidebarDebugView!
    private var webView: WKWebView!
    private var inputField: NSTextField!
    private var webViewReady = false
    private var pendingUpdate: [ChatMessageUI]?

    init(chatController: ChatController, windowTracker: WindowTracker, targetBounds: CGRect) {
        self.chatController = chatController
        self.windowTracker = windowTracker

        let frame = Self.sidebarFrame(forTargetBounds: targetBounds, sidebarWidth: sidebarWidth)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isReleasedWhenClosed = false
        self.level = .floating
        self.title = "Bones"
        self.isMovableByWindowBackground = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false

        setupUI()
        setupWindowTracking()
        chatController.delegate = self
    }

    // MARK: - Positioning

    static func sidebarFrame(forTargetBounds cgBounds: CGRect, sidebarWidth: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: sidebarWidth, height: 500)
        }
        let screenHeight = screen.frame.height
        let appKitY = screenHeight - cgBounds.origin.y - cgBounds.height
        return NSRect(
            x: cgBounds.origin.x + cgBounds.width + 4,
            y: appKitY,
            width: sidebarWidth,
            height: cgBounds.height
        )
    }

    private func setupWindowTracking() {
        windowTracker.onBoundsChanged = { [weak self] newBounds in
            guard let self else { return }
            let newFrame = Self.sidebarFrame(forTargetBounds: newBounds, sidebarWidth: self.sidebarWidth)
            self.setFrame(newFrame, display: true, animate: false)
        }
        windowTracker.onWindowClosed = { [weak self] in
            self?.close()
        }
        windowTracker.startTracking()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }
        contentView.wantsLayer = true

        let bgView = NSVisualEffectView(frame: contentView.bounds)
        bgView.material = .sidebar
        bgView.state = .active
        bgView.blendingMode = .behindWindow
        bgView.autoresizingMask = [.width, .height]
        contentView.addSubview(bgView)

        let tabsHeight: CGFloat = 32
        let contentHeight = contentView.bounds.height - tabsHeight

        tabControl = NSSegmentedControl(labels: ["Chat", "Debug"], trackingMode: .selectOne, target: self, action: #selector(tabChanged))
        tabControl.frame = NSRect(x: 8, y: contentHeight + 4, width: contentView.bounds.width - 16, height: 24)
        tabControl.selectedSegment = 0
        tabControl.autoresizingMask = [.width, .minYMargin]
        bgView.addSubview(tabControl)

        chatContainer = NSView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentHeight))
        chatContainer.autoresizingMask = [.width, .height]
        bgView.addSubview(chatContainer)

        debugView = SidebarDebugView(frame: chatContainer.frame)
        debugView.autoresizingMask = [.width, .height]
        debugView.isHidden = true
        bgView.addSubview(debugView)

        // Input area at bottom
        let inputHeight: CGFloat = 44
        let inputArea = NSView(frame: NSRect(
            x: 0, y: 0, width: chatContainer.bounds.width, height: inputHeight
        ))
        inputArea.autoresizingMask = [.width, .maxYMargin]

        inputField = NSTextField(frame: NSRect(
            x: 8, y: 8, width: chatContainer.bounds.width - 48, height: 28
        ))
        inputField.placeholderString = "Ask about this window..."
        inputField.bezelStyle = .roundedBezel
        inputField.autoresizingMask = [.width]
        inputField.target = self
        inputField.action = #selector(sendMessage)
        inputArea.addSubview(inputField)

        let sendButton = NSButton(frame: NSRect(
            x: chatContainer.bounds.width - 36, y: 8, width: 28, height: 28
        ))
        sendButton.bezelStyle = .texturedRounded
        sendButton.title = ">"
        sendButton.target = self
        sendButton.action = #selector(sendMessage)
        sendButton.autoresizingMask = [.minXMargin]
        inputArea.addSubview(sendButton)

        chatContainer.addSubview(inputArea)

        // WKWebView for chat messages
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false

        webView = WKWebView(frame: NSRect(
            x: 0, y: inputHeight,
            width: chatContainer.bounds.width,
            height: chatContainer.bounds.height - inputHeight
        ), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        chatContainer.addSubview(webView)

        loadChatHTML()
    }

    // MARK: - Chat HTML

    private func loadChatHTML() {
        // Load marked.js from bundle Resources
        let bundle = Bundle.main
        let markedPath = bundle.path(forResource: "marked.min", ofType: "js") ?? ""
        let markedURL = URL(fileURLWithPath: markedPath)

        var markedJS = ""
        if let data = try? Data(contentsOf: markedURL) {
            markedJS = String(data: data, encoding: .utf8) ?? ""
        }

        debugView.setVisible(false)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                padding: 8px;
                background: transparent;
                color: \(Self.cssColor(.labelColor));
                -webkit-user-select: text;
            }
            #messages { display: flex; flex-direction: column; gap: 6px; }
            .bubble {
                padding: 8px 12px;
                border-radius: 12px;
                max-width: 90%;
                word-wrap: break-word;
                overflow-wrap: break-word;
                line-height: 1.4;
            }
            .bubble.user {
                align-self: flex-end;
                background: rgba(0, 122, 255, 0.8);
                color: white;
            }
            .bubble.assistant {
                align-self: flex-start;
                background: rgba(128, 128, 128, 0.15);
                color: \(Self.cssColor(.labelColor));
            }
            .bubble p { margin: 0 0 8px 0; }
            .bubble p:last-child { margin-bottom: 0; }
            .bubble strong { font-weight: 600; }
            .bubble em { font-style: italic; }
            .bubble code {
                font-family: 'SF Mono', Menlo, monospace;
                font-size: 12px;
                background: rgba(0, 0, 0, 0.06);
                padding: 1px 4px;
                border-radius: 3px;
            }
            .bubble pre {
                background: rgba(0, 0, 0, 0.06);
                padding: 8px;
                border-radius: 6px;
                overflow-x: auto;
                margin: 6px 0;
            }
            .bubble pre code {
                background: none;
                padding: 0;
                font-size: 11.5px;
                line-height: 1.5;
            }
            .bubble ul, .bubble ol {
                padding-left: 20px;
                margin: 4px 0;
            }
            .bubble li { margin: 2px 0; }
            .bubble h1 { font-size: 17px; font-weight: 700; margin: 8px 0 4px 0; }
            .bubble h2 { font-size: 15px; font-weight: 700; margin: 6px 0 4px 0; }
            .bubble h3 { font-size: 14px; font-weight: 600; margin: 4px 0 2px 0; }
            .bubble.user code { background: rgba(255,255,255,0.2); }
            .bubble.user pre { background: rgba(255,255,255,0.15); }
            .bubble.user a { color: rgba(255,255,255,0.9); }
            .bubble a { color: #007AFF; text-decoration: none; }
            .streaming::after {
                content: ' \\25CF';
                animation: blink 1s infinite;
                color: rgba(128,128,128,0.5);
            }
            @keyframes blink { 50% { opacity: 0; } }
            .bubble.visualization {
                max-width: 100%;
                width: 100%;
                padding: 0;
                background: rgba(128, 128, 128, 0.08);
                border: 1px solid rgba(128, 128, 128, 0.2);
                overflow: hidden;
            }
            .viz-title {
                font-size: 11px;
                font-weight: 600;
                color: rgba(128, 128, 128, 0.7);
                padding: 6px 10px 4px 10px;
                border-bottom: 1px solid rgba(128, 128, 128, 0.15);
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .viz-frame {
                width: 100%;
                border: none;
                border-radius: 0 0 12px 12px;
                min-height: 60px;
                display: block;
                background: white;
            }
            @media (prefers-color-scheme: dark) {
                .bubble.assistant { background: rgba(255, 255, 255, 0.08); }
                .bubble code { background: rgba(255, 255, 255, 0.1); }
                .bubble pre { background: rgba(255, 255, 255, 0.08); }
                .bubble.visualization { background: rgba(255, 255, 255, 0.04); border-color: rgba(255,255,255,0.1); }
                .viz-title { color: rgba(255,255,255,0.5); border-bottom-color: rgba(255,255,255,0.08); }
            }
        </style>
        <script>\(markedJS)</script>
        <script>
            if (typeof marked !== 'undefined') {
                marked.setOptions({ breaks: true, gfm: true });
            }
            function renderMarkdown(text) {
                if (typeof marked !== 'undefined') {
                    return marked.parse(text);
                }
                // Fallback: escape HTML and preserve newlines
                return text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\\n/g,'<br>');
            }
            function updateMessages(messagesJSON) {
                var messages = JSON.parse(messagesJSON);
                var container = document.getElementById('messages');
                container.innerHTML = '';
                messages.forEach(function(msg) {
                    if (msg.visualizationHTML) {
                        var div = document.createElement('div');
                        div.className = 'bubble assistant visualization';
                        if (msg.visualizationTitle) {
                            var titleBar = document.createElement('div');
                            titleBar.className = 'viz-title';
                            titleBar.textContent = msg.visualizationTitle;
                            div.appendChild(titleBar);
                        }
                        var iframe = document.createElement('iframe');
                        iframe.className = 'viz-frame';
                        iframe.sandbox = 'allow-scripts';
                        iframe.srcdoc = msg.visualizationHTML;
                        iframe.style.height = '200px';
                        iframe.onload = function() {
                            try {
                                var h = iframe.contentDocument.documentElement.scrollHeight;
                                iframe.style.height = Math.min(Math.max(h, 60), 600) + 'px';
                            } catch(e) {}
                        };
                        div.appendChild(iframe);
                        container.appendChild(div);
                    } else {
                        var div = document.createElement('div');
                        div.className = 'bubble ' + msg.role;
                        if (msg.isStreaming) div.classList.add('streaming');
                        div.innerHTML = renderMarkdown(msg.text);
                        container.appendChild(div);
                    }
                });
                window.scrollTo(0, document.body.scrollHeight);
            }
        </script>
        </head>
        <body>
        <div id="messages"></div>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func cssColor(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#000" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = c.alphaComponent
        return "rgba(\(r),\(g),\(b),\(a))"
    }

    // MARK: - Actions

    @objc private func sendMessage() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        Task {
            await chatController.sendUserMessage(text)
        }
    }

    @objc private func tabChanged() {
        let showDebug = tabControl.selectedSegment == 1
        chatContainer.isHidden = showDebug
        debugView.isHidden = !showDebug
        debugView.setVisible(showDebug)
    }

    func toggleDebugTab() {
        let isDebug = tabControl.selectedSegment == 1
        tabControl.selectedSegment = isDebug ? 0 : 1
        tabChanged()
    }

    // MARK: - ChatControllerDelegate

    func chatControllerDidUpdateMessages(_ controller: ChatController) {
        let messages = controller.uiMessages
        if webViewReady {
            pushMessagesToWebView(messages)
        } else {
            pendingUpdate = messages
        }
    }

    func chatControllerDidEncounterError(_ controller: ChatController, error: String) {
        let alert = NSAlert()
        alert.messageText = "Chat Error"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - WebView Updates

    private func pushMessagesToWebView(_ messages: [ChatMessageUI]) {
        var jsonMessages: [[String: Any]] = []
        for msg in messages {
            var entry: [String: Any] = [
                "role": msg.role == .user ? "user" : "assistant",
                "text": msg.text,
                "isStreaming": msg.isStreaming
            ]
            if let vizHTML = msg.visualizationHTML {
                entry["visualizationHTML"] = vizHTML
            }
            if let vizTitle = msg.visualizationTitle {
                entry["visualizationTitle"] = vizTitle
            }
            jsonMessages.append(entry)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: jsonMessages),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }

        // Escape for JS string literal
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        webView.evaluateJavaScript("updateMessages('\(escaped)')")
    }

    // MARK: - Cleanup

    override func close() {
        ActiveAppState.shared.debugVisible = false
        InteractableOverlayWindow.shared.hideAll()
        windowTracker.stopTracking()
        super.close()
    }
}

// MARK: - WKNavigationDelegate

extension SidebarWindow: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewReady = true
        if let pending = pendingUpdate {
            pendingUpdate = nil
            pushMessagesToWebView(pending)
        }
    }
}

// NSView subclass with flipped coordinates for top-to-bottom layout
class NSFlippedView: NSView {
    override var isFlipped: Bool { true }
}
