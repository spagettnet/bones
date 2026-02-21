import AppKit
import WebKit

@MainActor
class OverlayUIWindow: NSPanel, WKScriptMessageHandler {
    private var webView: WKWebView!
    var onBridgeMessage: ((_ action: String, _ payload: [String: Any], _ callbackId: String) -> Void)?

    init(width: CGFloat, height: CGFloat) {
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        setupWebView(frame: frame)
    }

    private func setupWebView(frame: NSRect) {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Register bridge message handler
        userContentController.add(self, name: "bonesBridge")

        // Inject bridge JS at document start
        let bridgeScript = WKUserScript(
            source: Self.bridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(bridgeScript)

        config.userContentController = userContentController

        // Allow inline media, disable various restrictions for overlay use
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        self.contentView = webView
    }

    func loadHTML(_ html: String) {
        // Wrap in a full HTML document if not already wrapped
        let fullHTML: String
        if html.lowercased().contains("<html") {
            fullHTML = html
        } else {
            fullHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; overflow: hidden; }
                </style>
            </head>
            <body>
            \(html)
            </body>
            </html>
            """
        }
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    func evaluateJS(_ js: String) {
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                BoneLog.log("OverlayUIWindow: JS eval error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let messageName = MainActor.assumeIsolated { message.name }
        let messageBody = MainActor.assumeIsolated { message.body }

        guard messageName == "bonesBridge",
              let body = messageBody as? [String: Any],
              let action = body["action"] as? String,
              let callbackId = body["callbackId"] as? String
        else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]

        MainActor.assumeIsolated {
            self.onBridgeMessage?(action, payload, callbackId)
        }
    }

    // MARK: - Bridge JavaScript

    private static let bridgeJavaScript = """
    (function() {
        var pendingCallbacks = {};
        var callbackCounter = 0;

        window.__bonesBridge = {
            resolve: function(id, result) {
                if (pendingCallbacks[id]) {
                    pendingCallbacks[id].resolve(result);
                    delete pendingCallbacks[id];
                }
            },
            reject: function(id, error) {
                if (pendingCallbacks[id]) {
                    pendingCallbacks[id].reject(new Error(error));
                    delete pendingCallbacks[id];
                }
            }
        };

        function callBridge(action, payload) {
            return new Promise(function(resolve, reject) {
                var id = 'cb_' + (++callbackCounter);
                pendingCallbacks[id] = { resolve: resolve, reject: reject };
                window.webkit.messageHandlers.bonesBridge.postMessage({
                    action: action,
                    payload: payload || {},
                    callbackId: id
                });
            });
        }

        window.bones = {
            click: function(x, y) {
                return callBridge('click', { x: x, y: y });
            },
            typeText: function(text) {
                return callBridge('type_text', { text: text });
            },
            scroll: function(x, y, direction, amount) {
                return callBridge('scroll', { x: x, y: y, direction: direction, amount: amount || 3 });
            },
            takeScreenshot: function() {
                return callBridge('take_screenshot', {});
            },
            getTree: function() {
                return callBridge('get_tree', {});
            },
            getButtons: function() {
                return callBridge('get_buttons', {});
            },
            getInputFields: function() {
                return callBridge('get_input_fields', {});
            },
            getElements: function() {
                return callBridge('get_elements', {});
            },
            clickElement: function(label) {
                return callBridge('click_element', { label: label });
            },
            typeIntoField: function(label, text) {
                return callBridge('type_into_field', { label: label, text: text });
            },
            clickCode: function(code) {
                return callBridge('click_code', { code: code });
            },
            keyCombo: function(keys) {
                return callBridge('key_combo', { keys: keys });
            }
        };
    })();
    """
}
