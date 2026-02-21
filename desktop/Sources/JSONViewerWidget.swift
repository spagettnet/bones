import AppKit

@MainActor
class JSONViewerWidget: WidgetContentProvider {
    private let jsonString: String

    var preferredSize: NSSize { NSSize(width: 280, height: 200) }

    init(config: [String: Any]) {
        self.jsonString = config["json"] as? String ?? "{}"
    }

    func makeView(frame: NSRect) -> NSView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(white: 0.12, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textView.string = prettyPrintJSON(jsonString)

        scrollView.documentView = textView
        return scrollView
    }

    private func prettyPrintJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else { return raw }
        return result
    }
}
