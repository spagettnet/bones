import AppKit

@MainActor
class HighlightWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
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
        self.contentView = HighlightBorderView()
    }

    convenience init() {
        self.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    func highlight(frame cgFrame: CGRect) {
        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height
        // Convert CG (top-left origin) -> AppKit (bottom-left origin)
        let appKitFrame = NSRect(
            x: cgFrame.origin.x,
            y: screenHeight - cgFrame.origin.y - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
        self.setFrame(appKitFrame, display: true)
        self.orderFront(nil)
    }
}

class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let insetRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)

        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
        path.fill()

        path.lineWidth = 3
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        path.stroke()
    }
}
