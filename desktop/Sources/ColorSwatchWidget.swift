import AppKit

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6, let val = UInt64(hexStr, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

@MainActor
class ColorSwatchWidget: WidgetContentProvider {
    private let hexColor: String

    var preferredSize: NSSize { NSSize(width: 180, height: 100) }

    init(config: [String: Any]) {
        self.hexColor = config["color"] as? String ?? "#000000"
    }

    func makeView(frame: NSRect) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true

        let color = NSColor.fromHex(hexColor) ?? .black

        // Color swatch
        let swatchSize: CGFloat = 40
        let swatch = NSView(frame: NSRect(x: 12, y: frame.height - swatchSize - 12, width: swatchSize, height: swatchSize))
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(swatch)

        // Hex label
        let hexLabel = NSTextField(labelWithString: hexColor.uppercased())
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        hexLabel.frame = NSRect(x: 62, y: frame.height - 28, width: 110, height: 20)
        container.addSubview(hexLabel)

        // RGB breakdown
        let nsColor = color.usingColorSpace(.sRGB) ?? color
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        let rgbLabel = NSTextField(labelWithString: "R: \(r)  G: \(g)  B: \(b)")
        rgbLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        rgbLabel.textColor = .secondaryLabelColor
        rgbLabel.frame = NSRect(x: 62, y: frame.height - 48, width: 110, height: 16)
        container.addSubview(rgbLabel)

        // Copy button
        let copyBtn = NSButton(frame: NSRect(x: 12, y: 8, width: 60, height: 24))
        copyBtn.title = "Copy"
        copyBtn.bezelStyle = .texturedRounded
        copyBtn.target = self
        copyBtn.action = #selector(copyColor)
        container.addSubview(copyBtn)

        return container
    }

    @objc private func copyColor() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hexColor, forType: .string)
    }
}
