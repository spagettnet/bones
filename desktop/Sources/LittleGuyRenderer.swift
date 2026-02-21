import AppKit

@MainActor
enum LittleGuyRenderer {
    /// 18x18 template image for the menu bar (monochrome, adapts to dark/light mode)
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)

            let cx = rect.midX

            // Head
            ctx.fillEllipse(in: CGRect(x: cx - 3, y: 12, width: 6, height: 6))

            // Body
            ctx.move(to: CGPoint(x: cx, y: 12))
            ctx.addLine(to: CGPoint(x: cx, y: 5))
            ctx.strokePath()

            // Arms (slightly raised, waving)
            ctx.move(to: CGPoint(x: cx - 5, y: 10))
            ctx.addLine(to: CGPoint(x: cx, y: 8))
            ctx.addLine(to: CGPoint(x: cx + 5, y: 11))
            ctx.strokePath()

            // Legs
            ctx.move(to: CGPoint(x: cx, y: 5))
            ctx.addLine(to: CGPoint(x: cx - 4, y: 0))
            ctx.move(to: CGPoint(x: cx, y: 5))
            ctx.addLine(to: CGPoint(x: cx + 4, y: 0))
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// 48x48 colored image for the drag avatar
    static func dragImage() -> NSImage {
        let size = NSSize(width: 48, height: 48)
        return NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let cx = rect.midX

            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 3,
                color: NSColor.black.withAlphaComponent(0.3).cgColor
            )

            // Head (yellow circle)
            ctx.setFillColor(NSColor.systemYellow.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 8, y: 32, width: 16, height: 16))

            // Eyes
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 5, y: 38, width: 3, height: 3))
            ctx.fillEllipse(in: CGRect(x: cx + 2, y: 38, width: 3, height: 3))

            // Smile
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addArc(
                center: CGPoint(x: cx, y: 38),
                radius: 4,
                startAngle: .pi * 1.2,
                endAngle: .pi * 1.8,
                clockwise: false
            )
            ctx.strokePath()

            // Body
            ctx.setStrokeColor(NSColor.systemYellow.cgColor)
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: cx, y: 32))
            ctx.addLine(to: CGPoint(x: cx, y: 14))
            ctx.strokePath()

            // Arms (reaching down)
            ctx.move(to: CGPoint(x: cx - 12, y: 18))
            ctx.addLine(to: CGPoint(x: cx, y: 24))
            ctx.addLine(to: CGPoint(x: cx + 12, y: 18))
            ctx.strokePath()

            // Legs
            ctx.move(to: CGPoint(x: cx, y: 14))
            ctx.addLine(to: CGPoint(x: cx - 8, y: 2))
            ctx.move(to: CGPoint(x: cx, y: 14))
            ctx.addLine(to: CGPoint(x: cx + 8, y: 2))
            ctx.strokePath()

            return true
        }
    }
}
