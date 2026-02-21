import AppKit

@MainActor
class SidebarWindow: NSPanel, ChatControllerDelegate {
    private let sidebarWidth: CGFloat = 340
    private let chatController: ChatController
    private let windowTracker: WindowTracker
    private var tabControl: NSSegmentedControl!
    private var chatContainer: NSView!
    private var debugView: SidebarDebugView!
    private var scrollView: NSScrollView!
    private var messageContainer: NSView!
    private var inputField: NSTextField!

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
        // CG coords (top-left origin) → AppKit coords (bottom-left origin)
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

        // Background
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

        // Scroll view for messages
        scrollView = NSScrollView(frame: NSRect(
            x: 0, y: inputHeight,
            width: chatContainer.bounds.width,
            height: chatContainer.bounds.height - inputHeight
        ))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        messageContainer = NSFlippedView(frame: NSRect(
            x: 0, y: 0, width: scrollView.bounds.width, height: 0
        ))
        messageContainer.autoresizingMask = [.width]
        scrollView.documentView = messageContainer

        chatContainer.addSubview(scrollView)
        debugView.setVisible(false)
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
        rebuildMessageViews(controller.uiMessages)
    }

    func chatControllerDidEncounterError(_ controller: ChatController, error: String) {
        let alert = NSAlert()
        alert.messageText = "Chat Error"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Message Rendering

    private func rebuildMessageViews(_ messages: [ChatMessageUI]) {
        for subview in messageContainer.subviews {
            subview.removeFromSuperview()
        }

        let containerWidth = scrollView.bounds.width
        var yOffset: CGFloat = 8

        for message in messages {
            let bubble = createBubble(for: message, containerWidth: containerWidth, yOffset: yOffset)
            messageContainer.addSubview(bubble)
            yOffset += bubble.frame.height + 6
        }

        messageContainer.frame.size.height = max(yOffset + 8, scrollView.bounds.height)
        scrollToBottom()
    }

    private func createBubble(for message: ChatMessageUI, containerWidth: CGFloat, yOffset: CGFloat) -> NSView {
        let isUser = message.role == .user
        let maxBubbleWidth = containerWidth - 60
        let padding: CGFloat = 10

        // Measure text
        let font = NSFont.systemFont(ofSize: 13)
        let textWidth = maxBubbleWidth - 2 * padding
        let attrString = NSAttributedString(string: message.text, attributes: [.font: font])
        let textRect = attrString.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let bubbleHeight = ceil(textRect.height) + 2 * padding
        let bubbleWidth = min(ceil(textRect.width) + 2 * padding + 4, maxBubbleWidth)

        let bubbleX: CGFloat = isUser ? containerWidth - bubbleWidth - 12 : 12

        let bubbleView = NSView(frame: NSRect(x: bubbleX, y: yOffset, width: bubbleWidth, height: bubbleHeight))
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 12

        if isUser {
            bubbleView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        } else {
            bubbleView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.15).cgColor
        }

        let label = NSTextField(wrappingLabelWithString: message.text)
        label.frame = NSRect(x: padding, y: padding, width: textWidth, height: ceil(textRect.height))
        label.font = font
        label.isEditable = false
        label.isSelectable = true
        label.drawsBackground = false
        label.isBordered = false
        label.textColor = isUser ? .white : .labelColor

        if message.isStreaming {
            label.stringValue = message.text + " ..."
        }

        bubbleView.addSubview(label)
        return bubbleView
    }

    private func scrollToBottom() {
        guard let documentView = scrollView.documentView else { return }
        let maxScrollY = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Cleanup

    override func close() {
        ActiveAppState.shared.debugVisible = false
        InteractableOverlayWindow.shared.hideAll()
        windowTracker.stopTracking()
        super.close()
    }
}

// NSView subclass with flipped coordinates for top-to-bottom layout
class NSFlippedView: NSView {
    override var isFlipped: Bool { true }
}
