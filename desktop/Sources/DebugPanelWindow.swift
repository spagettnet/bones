import AppKit

@MainActor
class DebugPanelWindow: NSWindow {
    static let shared = DebugPanelWindow()
    private static let panelWidth: CGFloat = 280
    private static let panelGap: CGFloat = 8

    var wantsVisible = false

    // Retained references for fast updates (mouse + element)
    private var mouseLabel: NSTextField?
    private var elementLabel: NSTextField?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = true
        self.isReleasedWhenClosed = false
    }

    func toggle() {
        if wantsVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard ActiveAppState.shared.isActive else { return }
        wantsVisible = true
        refresh()
        reposition()
        self.orderFront(nil)
    }

    func hide() {
        wantsVisible = false
        self.orderOut(nil)
    }

    /// Fast path: only updates mouse + element labels (called at ~60Hz from mouse handler)
    func refreshFastState() {
        guard wantsVisible else { return }
        let state = ActiveAppState.shared

        if let label = mouseLabel {
            label.stringValue = "x: \(Int(state.mouseLocation.x)), y: \(Int(state.mouseLocation.y))"
        }
        if let label = elementLabel {
            label.stringValue = state.elementUnderCursor?.summary ?? "—"
        }
    }

    func refresh() {
        guard wantsVisible else { return }
        let state = ActiveAppState.shared
        guard state.isActive else {
            hide()
            return
        }

        // Reset fast-update references
        mouseLabel = nil
        elementLabel = nil

        let bgView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 300))
        bgView.material = .hudWindow
        bgView.state = .active
        bgView.blendingMode = .behindWindow
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 12
        bgView.layer?.masksToBounds = true

        var y: CGFloat = 0

        // Kick Off button at bottom
        let kickOff = NSButton(frame: NSRect(x: 20, y: 16, width: Self.panelWidth - 40, height: 32))
        kickOff.title = "Kick Off"
        kickOff.bezelStyle = .rounded
        kickOff.contentTintColor = .systemRed
        kickOff.font = .systemFont(ofSize: 13, weight: .semibold)
        kickOff.target = self
        kickOff.action = #selector(kickOffClicked)
        bgView.addSubview(kickOff)
        y = 60

        // Screenshots section
        let screenshotHeader = makeLabel("Screenshots", size: 11, weight: .medium, color: .secondaryLabelColor)
        let screenshotEntries: [NSTextField]
        if state.screenshots.isEmpty {
            screenshotEntries = [makeLabel("No captures yet", size: 12, weight: .regular, color: .tertiaryLabelColor)]
        } else {
            screenshotEntries = state.screenshots.reversed().map { entry in
                let relTime = relativeTime(from: entry.date)
                return makeLabel(relTime, size: 12, weight: .regular, color: .labelColor)
            }
        }

        for entry in screenshotEntries {
            entry.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 18)
            bgView.addSubview(entry)
            y += 20
        }
        screenshotHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(screenshotHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Context Tree section
        let treeHeader = makeLabel("Context Tree", size: 11, weight: .medium, color: .secondaryLabelColor)
        let treeHeight: CGFloat = 200
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: treeHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let treeText = NSTextView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth - 56, height: treeHeight))
        treeText.isEditable = false
        treeText.isSelectable = true
        treeText.drawsBackground = false
        treeText.textColor = .labelColor
        treeText.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        treeText.string = state.contextTree?.treeString() ?? "Waiting for tree..."
        treeText.textContainerInset = NSSize(width: 0, height: 4)
        treeText.isVerticallyResizable = true
        treeText.textContainer?.widthTracksTextView = true
        scrollView.documentView = treeText
        bgView.addSubview(scrollView)
        y += treeHeight + 4

        treeHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(treeHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Input Boxes section
        let inputHeader = makeLabel("Input Fields (\(state.inputFields.count))", size: 11, weight: .medium, color: .secondaryLabelColor)
        let inputHeight: CGFloat = 80
        let inputText: String
        if state.inputFields.isEmpty {
            inputText = "None found"
        } else {
            inputText = state.inputFields.map { node in
                let label = node.title ?? node.description ?? node.roleDescription ?? "untitled"
                return "\(node.role): \"\(label)\""
            }.joined(separator: "\n")
        }
        let inputScroll = makeScrollableText(inputText, height: inputHeight, color: .systemBlue)
        inputScroll.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: inputHeight)
        bgView.addSubview(inputScroll)
        y += inputHeight + 4
        inputHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(inputHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Clickable Buttons section
        let buttonsHeader = makeLabel("Clickable Buttons (\(state.buttons.count))", size: 11, weight: .medium, color: .secondaryLabelColor)
        let buttonsHeight: CGFloat = 160
        let buttonsText: String
        if state.buttons.isEmpty {
            buttonsText = "None found"
        } else {
            buttonsText = state.buttons.map { node in
                let label = node.title ?? node.description ?? node.roleDescription ?? "untitled"
                return label
            }.joined(separator: "\n")
        }
        let buttonsScroll = makeScrollableText(buttonsText, height: buttonsHeight, color: .systemOrange)
        buttonsScroll.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: buttonsHeight)
        bgView.addSubview(buttonsScroll)
        y += buttonsHeight + 4
        buttonsHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(buttonsHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Element Under Cursor
        let elemHeader = makeLabel("Element Under Cursor", size: 11, weight: .medium, color: .secondaryLabelColor)
        let elemValue = makeLabel(state.elementUnderCursor?.summary ?? "—", size: 12, weight: .regular, color: .labelColor)
        elemValue.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 18)
        bgView.addSubview(elemValue)
        self.elementLabel = elemValue
        y += 20
        elemHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(elemHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Mouse location
        let mouseHeader = makeLabel("Mouse", size: 11, weight: .medium, color: .secondaryLabelColor)
        let mouseValue = NSTextField(labelWithString: "x: \(Int(state.mouseLocation.x)), y: \(Int(state.mouseLocation.y))")
        mouseValue.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        mouseValue.textColor = .labelColor
        mouseValue.lineBreakMode = .byTruncatingTail
        mouseValue.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 18)
        bgView.addSubview(mouseValue)
        self.mouseLabel = mouseValue
        y += 20
        mouseHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(mouseHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Focus state
        let focusHeader = makeLabel("Focus", size: 11, weight: .medium, color: .secondaryLabelColor)
        let focusDot = state.isFocused ? "\u{1F7E2}" : "\u{1F534}"
        let focusText = state.isFocused ? "Focused" : "Not Focused"
        let focusValue = makeLabel("\(focusDot) \(focusText)", size: 12, weight: .regular, color: .labelColor)
        focusValue.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 18)
        bgView.addSubview(focusValue)
        y += 20
        focusHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(focusHeader)
        y += 26

        y = addSeparator(to: bgView, y: y)

        // Window Title
        if let title = state.windowTitle, !title.isEmpty {
            let titleLabel = makeLabel(title, size: 12, weight: .regular, color: .labelColor)
            titleLabel.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 18)
            bgView.addSubview(titleLabel)
            y += 20

            let titleHeader = makeLabel("Window Title", size: 11, weight: .medium, color: .secondaryLabelColor)
            titleHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
            bgView.addSubview(titleHeader)
            y += 26

            y = addSeparator(to: bgView, y: y)
        }

        // App Name
        let appLabel = makeLabel(state.appName, size: 14, weight: .bold, color: .labelColor)
        appLabel.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 20)
        bgView.addSubview(appLabel)
        y += 22

        let appHeader = makeLabel("App Name", size: 11, weight: .medium, color: .secondaryLabelColor)
        appHeader.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 16)
        bgView.addSubview(appHeader)
        y += 30

        // Header with close button
        let headerLabel = makeLabel("Bones Debug", size: 15, weight: .bold, color: .white)
        headerLabel.frame = NSRect(x: 20, y: y, width: Self.panelWidth - 60, height: 22)
        bgView.addSubview(headerLabel)

        let closeBtn = NSButton(frame: NSRect(x: Self.panelWidth - 36, y: y, width: 20, height: 20))
        closeBtn.bezelStyle = .circular
        closeBtn.title = "X"
        closeBtn.font = .systemFont(ofSize: 10, weight: .bold)
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        bgView.addSubview(closeBtn)
        y += 30

        let totalHeight = y
        bgView.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: totalHeight)
        self.contentView = bgView

        let currentTopLeft = NSPoint(x: self.frame.origin.x, y: self.frame.maxY)
        let newFrame = NSRect(
            x: currentTopLeft.x,
            y: currentTopLeft.y - totalHeight,
            width: Self.panelWidth,
            height: totalHeight
        )
        self.setFrame(newFrame, display: true)
    }

    func reposition() {
        guard wantsVisible, ActiveAppState.shared.isActive else { return }
        let state = ActiveAppState.shared
        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height

        let appKitFrame = NSRect(
            x: state.windowBounds.origin.x,
            y: screenHeight - state.windowBounds.origin.y - state.windowBounds.height,
            width: state.windowBounds.width,
            height: state.windowBounds.height
        )

        let panelHeight = self.frame.height

        let rightX = appKitFrame.maxX + Self.panelGap
        let leftX = appKitFrame.minX - Self.panelWidth - Self.panelGap

        let x: CGFloat
        if rightX + Self.panelWidth <= screen.frame.maxX {
            x = rightX
        } else if leftX >= screen.frame.minX {
            x = leftX
        } else {
            x = rightX
        }

        let y = appKitFrame.maxY - panelHeight

        self.setFrame(NSRect(x: x, y: y, width: Self.panelWidth, height: panelHeight), display: true)
    }

    @objc private func kickOffClicked() {
        ActiveAppState.shared.detach()
    }

    @objc private func closeClicked() {
        hide()
    }

    private func addSeparator(to view: NSView, y: CGFloat) -> CGFloat {
        let sep = NSBox(frame: NSRect(x: 20, y: y, width: Self.panelWidth - 40, height: 1))
        sep.boxType = .separator
        view.addSubview(sep)
        return y + 12
    }

    private func makeScrollableText(_ text: String, height: CGFloat, color: NSColor) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth - 40, height: height))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth - 56, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = color
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.string = text
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
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
}
