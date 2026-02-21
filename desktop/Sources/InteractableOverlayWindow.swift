import AppKit

@MainActor
class InteractableOverlayWindow: NSWindow {
    static let shared = InteractableOverlayWindow()
    private var tagWindows: [NSWindow] = []

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
    }

    func updateOverlays() {
        guard DebugPanelWindow.shared.wantsVisible else {
            hideAll()
            return
        }

        let state = ActiveAppState.shared
        guard state.isActive else {
            hideAll()
            return
        }

        hideAll()

        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height

        for button in state.buttons {
            guard let frame = button.frame else { continue }
            let label = button.title ?? button.description ?? button.roleDescription ?? "btn"
            let tag = makeTag(
                text: label,
                cgFrame: frame,
                screenHeight: screenHeight,
                color: NSColor.systemOrange.withAlphaComponent(0.85),
                borderColor: NSColor.systemOrange
            )
            tag.orderFront(nil)
            tagWindows.append(tag)
        }

        for input in state.inputFields {
            guard let frame = input.frame else { continue }
            let label = input.title ?? input.description ?? input.roleDescription ?? "input"
            let tag = makeTag(
                text: label,
                cgFrame: frame,
                screenHeight: screenHeight,
                color: NSColor.systemBlue.withAlphaComponent(0.85),
                borderColor: NSColor.systemBlue
            )
            tag.orderFront(nil)
            tagWindows.append(tag)
        }
    }

    func hideAll() {
        for w in tagWindows {
            w.orderOut(nil)
        }
        tagWindows.removeAll()
    }

    private func makeTag(text: String, cgFrame: CGRect, screenHeight: CGFloat, color: NSColor, borderColor: NSColor) -> NSWindow {
        let tagHeight: CGFloat = 14
        let padding: CGFloat = 4
        let truncated = text.count > 20 ? String(text.prefix(20)) + "..." : text
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)

        // Measure text width
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (truncated as NSString).size(withAttributes: attrs)
        let tagWidth = textSize.width + padding * 2

        // Convert CG frame (top-left origin) to AppKit (bottom-left origin)
        // Place tag at top-left corner of the element
        let appKitY = screenHeight - cgFrame.origin.y - tagHeight

        let window = NSWindow(
            contentRect: NSRect(x: cgFrame.origin.x, y: appKitY, width: tagWidth, height: tagHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let tagView = TagView(frame: NSRect(x: 0, y: 0, width: tagWidth, height: tagHeight))
        tagView.text = truncated
        tagView.bgColor = color
        tagView.borderColor = borderColor
        tagView.font = font
        window.contentView = tagView

        return window
    }
}

private class TagView: NSView {
    var text: String = ""
    var bgColor: NSColor = .systemOrange
    var borderColor: NSColor = .systemOrange
    var font: NSFont = .systemFont(ofSize: 9, weight: .semibold)

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)

        bgColor.withAlphaComponent(0.9).setFill()
        path.fill()

        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
