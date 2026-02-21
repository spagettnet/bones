import AppKit

@MainActor
class WidgetWindow: NSPanel {
    let widgetId: String
    var anchorImageX: Int
    var anchorImageY: Int

    init(widgetId: String, title: String, contentProvider: WidgetContentProvider, anchorImageX: Int, anchorImageY: Int) {
        self.widgetId = widgetId
        self.anchorImageX = anchorImageX
        self.anchorImageY = anchorImageY

        let size = contentProvider.preferredSize
        let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isReleasedWhenClosed = false
        self.level = .floating
        self.title = title
        self.isMovableByWindowBackground = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false

        let widgetView = contentProvider.makeView(frame: NSRect(origin: .zero, size: size))
        widgetView.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(widgetView)
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        // dy comes from CG coords (top-left origin), but NSWindow uses bottom-left,
        // so invert Y
        var origin = self.frame.origin
        origin.x += dx
        origin.y -= dy
        self.setFrameOrigin(origin)
    }
}
