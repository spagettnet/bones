import AppKit

@MainActor
enum FeedbackWindow {
    private static var currentWindow: NSWindow?

    static func show(message: String, detail: String) {
        currentWindow?.close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.center()

        let bgView = NSVisualEffectView(frame: window.contentView!.bounds)
        bgView.material = .hudWindow
        bgView.state = .active
        bgView.blendingMode = .behindWindow
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 12
        bgView.layer?.masksToBounds = true
        window.contentView = bgView

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 35, width: 300, height: 25)
        bgView.addSubview(label)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.frame = NSRect(x: 10, y: 12, width: 300, height: 18)
        bgView.addSubview(detailLabel)

        window.alphaValue = 0
        window.orderFront(nil)
        currentWindow = window

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak window] in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    window.close()
                    if currentWindow === window { currentWindow = nil }
                }
            })
        }
    }
}
