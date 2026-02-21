import AppKit

@MainActor
final class SidebarDebugView: NSView {
    private var infoLabel: NSTextField!
    private var screenshotLabel: NSTextField!
    private var buttonsHeader: NSTextField!
    private var inputsHeader: NSTextField!
    private var treeHeader: NSTextField!
    private var buttonsScrollView: NSScrollView!
    private var inputsScrollView: NSScrollView!
    private var treeScrollView: NSScrollView!
    private var buttonsTextView: NSTextView!
    private var inputsTextView: NSTextView!
    private var treeTextView: NSTextView!
    private var refreshTimer: Timer?
    private var lastInfoText = ""
    private var lastScreenshotText = ""
    private var lastButtonsText = ""
    private var lastInputsText = ""
    private var lastTreeText = ""
    private var lastTreeRefreshTime: CFAbsoluteTime = 0
    
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func setVisible(_ visible: Bool) {
        ActiveAppState.shared.debugVisible = visible
        if !visible {
            stopRefreshTimer()
            InteractableOverlayWindow.shared.hideAll()
        } else {
            startRefreshTimer()
            refresh()
            InteractableOverlayWindow.shared.updateOverlays()
        }
    }

    func refresh() {
        guard ActiveAppState.shared.debugVisible else { return }
        let state = ActiveAppState.shared
        let focused = state.isFocused ? "yes" : "no"
        let title = state.windowTitle ?? "(none)"
        let mouse = "x: \(Int(state.mouseLocation.x)), y: \(Int(state.mouseLocation.y))"
        let element = state.elementUnderCursor?.summary ?? "-"

        let infoText = """
        App: \(state.appName)
        Window title: \(title)
        Focused: \(focused)
        Mouse: \(mouse)
        Element under cursor: \(element)
        """
        if infoText != lastInfoText {
            infoLabel.stringValue = infoText
            lastInfoText = infoText
        }

        let screenshotText = screenshotSummary(state: state)
        if screenshotText != lastScreenshotText {
            screenshotLabel.stringValue = screenshotText
            lastScreenshotText = screenshotText
        }

        buttonsHeader.stringValue = "Clickable Buttons (\(state.buttons.count))"
        inputsHeader.stringValue = "Input Fields (\(state.inputFields.count))"
        
        let buttonsText = buttonsSummary(state: state)
        if buttonsText != lastButtonsText {
            updateTextView(buttonsTextView, in: buttonsScrollView, text: buttonsText)
            lastButtonsText = buttonsText
        }
        
        let inputsText = inputsSummary(state: state)
        if inputsText != lastInputsText {
            updateTextView(inputsTextView, in: inputsScrollView, text: inputsText)
            lastInputsText = inputsText
        }
        
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTreeRefreshTime >= 1.0 || lastTreeText.isEmpty {
            lastTreeRefreshTime = now
            let treeText = state.contextTree?.treeString() ?? "Waiting for tree..."
            if treeText != lastTreeText {
                updateTextView(treeTextView, in: treeScrollView, text: treeText)
                lastTreeText = treeText
            }
        }
    }

    private func setupUI() {
        wantsLayer = true

        let kickOff = NSButton(frame: NSRect(x: 12, y: 10, width: 96, height: 28))
        kickOff.title = "Kick Off"
        kickOff.bezelStyle = .rounded
        kickOff.contentTintColor = .systemRed
        kickOff.font = .systemFont(ofSize: 12, weight: .semibold)
        kickOff.target = self
        kickOff.action = #selector(kickOffClicked)
        kickOff.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(kickOff)

        infoLabel = makeWrappingLabel(font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        addSubview(infoLabel)

        screenshotLabel = makeWrappingLabel(font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        addSubview(screenshotLabel)

        buttonsHeader = makeHeader("Clickable Buttons")
        addSubview(buttonsHeader)
        buttonsTextView = makeTextView()
        buttonsScrollView = makeScrollView(for: buttonsTextView)
        addSubview(buttonsScrollView)

        inputsHeader = makeHeader("Input Fields")
        addSubview(inputsHeader)
        inputsTextView = makeTextView()
        inputsScrollView = makeScrollView(for: inputsTextView)
        addSubview(inputsScrollView)

        treeHeader = makeHeader("Context Tree")
        addSubview(treeHeader)
        treeTextView = makeTextView()
        treeScrollView = makeScrollView(for: treeTextView)
        addSubview(treeScrollView)

        layoutDebugSubviews()
        refresh()
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func layout() {
        super.layout()
        layoutDebugSubviews()
    }

    private func layoutDebugSubviews() {
        let side: CGFloat = 12
        let headerHeight: CGFloat = 16
        let width = bounds.width - side * 2
        var y: CGFloat = 8

        let kickOffHeight: CGFloat = 28

        infoLabel.frame = NSRect(x: side, y: y + kickOffHeight + 6, width: width, height: 86)
        y += kickOffHeight + 6 + 92

        screenshotLabel.frame = NSRect(x: side, y: y, width: width, height: 44)
        y += 50

        buttonsHeader.frame = NSRect(x: side, y: y, width: width, height: headerHeight)
        y += headerHeight + 4
        buttonsScrollView.frame = NSRect(x: side, y: y, width: width, height: 110)
        y += 118

        inputsHeader.frame = NSRect(x: side, y: y, width: width, height: headerHeight)
        y += headerHeight + 4
        inputsScrollView.frame = NSRect(x: side, y: y, width: width, height: 90)
        y += 98

        treeHeader.frame = NSRect(x: side, y: y, width: width, height: headerHeight)
        y += headerHeight + 4
        let treeHeight = max(90, bounds.height - y - 10)
        treeScrollView.frame = NSRect(x: side, y: y, width: width, height: treeHeight)
        
        if let kickOff = subviews.first(where: { ($0 as? NSButton)?.title == "Kick Off" }) {
            kickOff.frame = NSRect(x: side, y: 8, width: 96, height: kickOffHeight)
        }
    }

    private func screenshotSummary(state: ActiveAppState) -> String {
        guard let latest = state.screenshots.last else {
            return "Screenshots: none"
        }
        return "Last screenshot: \(latest.filename) (\(relativeTime(from: latest.date)))\nTotal captures: \(state.screenshots.count)"
    }

    private func buttonsSummary(state: ActiveAppState) -> String {
        if state.buttons.isEmpty { return "None found" }
        return state.buttons.map { node in
            node.title ?? node.description ?? node.roleDescription ?? "untitled"
        }.joined(separator: "\n")
    }

    private func inputsSummary(state: ActiveAppState) -> String {
        if state.inputFields.isEmpty { return "None found" }
        return state.inputFields.map { node in
            let label = node.title ?? node.description ?? node.roleDescription ?? "untitled"
            return "\(node.role): \(label)"
        }.joined(separator: "\n")
    }

    private func makeHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeWrappingLabel(font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeTextView() -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    private func makeScrollView(for textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        scroll.documentView = textView
        return scroll
    }
    
    private func updateTextView(_ textView: NSTextView, in scrollView: NSScrollView, text: String) {
        textView.string = text
        let width = max(120, scrollView.contentSize.width - 8)
        let attrs: [NSAttributedString.Key: Any] = [.font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let height = max(scrollView.contentSize.height, ceil(measured.height) + 12)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    @objc private func kickOffClicked() {
        ActiveAppState.shared.detach()
    }
}
