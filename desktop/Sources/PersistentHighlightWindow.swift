import AppKit

@MainActor
class PersistentHighlightWindow: NSWindow {
    static let shared = PersistentHighlightWindow()

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
        self.contentView = HighlightBorderView()
    }

    func highlight(frame cgFrame: CGRect) {
        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height
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
