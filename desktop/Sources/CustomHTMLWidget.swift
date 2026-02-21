import AppKit
import WebKit

@MainActor
class CustomHTMLWidget: WidgetContentProvider {
    private let html: String
    private let widgetWidth: Int
    private let widgetHeight: Int

    var preferredSize: NSSize {
        NSSize(width: CGFloat(widgetWidth), height: CGFloat(widgetHeight))
    }

    init(config: [String: Any]) {
        self.html = config["html"] as? String ?? "<p>Empty widget</p>"
        self.widgetWidth = config["width"] as? Int ?? 300
        self.widgetHeight = config["height"] as? Int ?? 200
    }

    func makeView(frame: NSRect) -> NSView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        let fullHTML = """
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
                color: #e0e0e0;
                background: #1e1e1e;
                overflow: auto;
            }
            @media (prefers-color-scheme: light) {
                body { color: #333; background: #f5f5f5; }
            }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """

        webView.loadHTMLString(fullHTML, baseURL: nil)
        return webView
    }
}
