import AppKit

@MainActor
class CodeSnippetWidget: WidgetContentProvider {
    private let code: String
    private let language: String

    var preferredSize: NSSize { NSSize(width: 320, height: 180) }

    init(config: [String: Any]) {
        self.code = config["code"] as? String ?? ""
        self.language = config["language"] as? String ?? ""
    }

    func makeView(frame: NSRect) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true

        // Language label
        let labelHeight: CGFloat = 20
        let langLabel = NSTextField(labelWithString: language.isEmpty ? "code" : language)
        langLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        langLabel.textColor = .tertiaryLabelColor
        langLabel.frame = NSRect(x: 8, y: frame.height - labelHeight - 4, width: frame.width - 16, height: labelHeight)
        container.addSubview(langLabel)

        // Code scroll view
        let codeTop = frame.height - labelHeight - 8
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: frame.width, height: codeTop))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.frame.size))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.backgroundColor = NSColor(white: 0.12, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = code

        scrollView.documentView = textView
        container.addSubview(scrollView)

        return container
    }
}
