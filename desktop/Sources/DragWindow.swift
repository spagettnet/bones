import AppKit

@MainActor
class DragWindow: NSWindow {
    init(image: NSImage) {
        let size = NSSize(width: 48, height: 48)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.ignoresMouseEvents = true
        self.hasShadow = true
        self.alphaValue = 0.9
        self.isReleasedWhenClosed = false

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        self.contentView = imageView
    }

    func followMouse(at point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - 10, y: point.y - 40))
    }
}
