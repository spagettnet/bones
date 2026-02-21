import AppKit
import QuartzCore

/// Procedural dog sprite that runs along the title bar,
/// picks up a bone, and runs off.
@MainActor
class DogAnimation {
    private var dogWindow: NSWindow?
    private var dogView: DogSpriteView?
    private var animationTimer: Timer?
    private var cancelled = false

    // Animation state
    private var phase: Phase = .enteringLeft
    private var dogX: CGFloat = 0
    private var targetBoneX: CGFloat = 0
    private var titleBarY: CGFloat = 0
    private var screenMinX: CGFloat = 0
    private var screenMaxX: CGFloat = 0
    private var onBonePickup: (() -> Void)?
    private var onComplete: (() -> Void)?
    private var frameCount: Int = 0
    private var pauseTimer: Int = 0

    private let dogSpeed: CGFloat = 320
    private let dogExitSpeed: CGFloat = 400
    private let dogSize = NSSize(width: 48, height: 32)
    private let pauseFrames: Int = 18  // 0.3s at 60fps

    enum Phase {
        case enteringLeft    // running from right toward bone
        case pausing         // stopped at bone
        case exitingRight    // running away with bone
    }

    func run(
        titleBarY: CGFloat,
        screenMinX: CGFloat,
        screenMaxX: CGFloat,
        bonePosition: NSPoint,
        onBonePickup: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.titleBarY = titleBarY
        self.screenMinX = screenMinX
        self.screenMaxX = screenMaxX
        self.targetBoneX = bonePosition.x
        self.onBonePickup = onBonePickup
        self.onComplete = completion

        // Start from the right edge
        dogX = screenMaxX + 10
        phase = .enteringLeft

        // Create dog window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: dogSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false

        let view = DogSpriteView(frame: NSRect(origin: .zero, size: dogSize))
        window.contentView = view
        self.dogView = view
        self.dogWindow = window

        updateWindowPosition()
        window.orderFront(nil)

        // Start animation
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func cancel() {
        cancelled = true
        animationTimer?.invalidate()
        animationTimer = nil
        dogWindow?.close()
        dogWindow = nil
    }

    private func tick() {
        guard !cancelled else { return }

        frameCount += 1
        let dt: CGFloat = 1.0 / 60.0

        switch phase {
        case .enteringLeft:
            dogX -= dogSpeed * dt
            dogView?.facingLeft = true
            dogView?.hasBone = false
            dogView?.isRunning = true
            dogView?.runFrame = (frameCount / 6) % 2  // Alternate legs every 6 frames

            if dogX <= targetBoneX {
                dogX = targetBoneX
                phase = .pausing
                pauseTimer = 0
                dogView?.isRunning = false
            }

        case .pausing:
            pauseTimer += 1
            if pauseTimer == 8 {
                // Pick up the bone partway through the pause
                onBonePickup?()
                onBonePickup = nil
                dogView?.hasBone = true
            }
            if pauseTimer >= pauseFrames {
                phase = .exitingRight
                dogView?.facingLeft = false
                dogView?.isRunning = true
            }

        case .exitingRight:
            dogX += dogExitSpeed * dt
            dogView?.runFrame = (frameCount / 5) % 2  // Slightly faster leg cycle

            if dogX > screenMaxX + dogSize.width + 20 {
                // Done!
                animationTimer?.invalidate()
                animationTimer = nil
                dogWindow?.close()
                dogWindow = nil
                onComplete?()
            }
        }

        updateWindowPosition()
        dogView?.setNeedsDisplay(dogView!.bounds)
    }

    private func updateWindowPosition() {
        dogWindow?.setFrameOrigin(NSPoint(
            x: dogX - dogSize.width / 2,
            y: titleBarY - 5
        ))
    }
}

// MARK: - Dog Sprite View

@MainActor
class DogSpriteView: NSView {
    var facingLeft = true
    var isRunning = false
    var runFrame = 0
    var hasBone = false

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()

        // Flip for facing direction
        if !facingLeft {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }

        drawDog(in: ctx, size: bounds.size)

        ctx.restoreGState()
    }

    private func drawDog(in ctx: CGContext, size: CGSize) {
        let bodyColor = NSColor(calibratedRed: 0.65, green: 0.45, blue: 0.25, alpha: 1.0).cgColor
        let darkColor = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.15, alpha: 1.0).cgColor
        let noseColor = NSColor.black.cgColor
        let eyeColor = NSColor.black.cgColor

        let groundY: CGFloat = 4
        let bodyW: CGFloat = 24
        let bodyH: CGFloat = 12
        let bodyX: CGFloat = 10
        let bodyY: CGFloat = groundY + 8

        // Legs
        ctx.setStrokeColor(darkColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)

        if isRunning {
            if runFrame == 0 {
                // Front legs: one forward, one back
                ctx.move(to: CGPoint(x: bodyX + 5, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + 1, y: groundY))
                ctx.move(to: CGPoint(x: bodyX + 8, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + 12, y: groundY))
                // Back legs
                ctx.move(to: CGPoint(x: bodyX + bodyW - 8, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + bodyW - 12, y: groundY))
                ctx.move(to: CGPoint(x: bodyX + bodyW - 5, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + bodyW - 1, y: groundY))
            } else {
                // Alternate position
                ctx.move(to: CGPoint(x: bodyX + 5, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + 8, y: groundY))
                ctx.move(to: CGPoint(x: bodyX + 8, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + 4, y: groundY))
                // Back legs
                ctx.move(to: CGPoint(x: bodyX + bodyW - 8, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + bodyW - 4, y: groundY))
                ctx.move(to: CGPoint(x: bodyX + bodyW - 5, y: bodyY))
                ctx.addLine(to: CGPoint(x: bodyX + bodyW - 9, y: groundY))
            }
        } else {
            // Standing still
            ctx.move(to: CGPoint(x: bodyX + 5, y: bodyY))
            ctx.addLine(to: CGPoint(x: bodyX + 5, y: groundY))
            ctx.move(to: CGPoint(x: bodyX + 9, y: bodyY))
            ctx.addLine(to: CGPoint(x: bodyX + 9, y: groundY))
            ctx.move(to: CGPoint(x: bodyX + bodyW - 9, y: bodyY))
            ctx.addLine(to: CGPoint(x: bodyX + bodyW - 9, y: groundY))
            ctx.move(to: CGPoint(x: bodyX + bodyW - 5, y: bodyY))
            ctx.addLine(to: CGPoint(x: bodyX + bodyW - 5, y: groundY))
        }
        ctx.strokePath()

        // Body
        ctx.setFillColor(bodyColor)
        let bodyRect = CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH)
        let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(bodyPath)
        ctx.fillPath()

        // Head
        let headX: CGFloat = bodyX - 6
        let headY: CGFloat = bodyY + bodyH - 4
        let headSize: CGFloat = 12
        ctx.fillEllipse(in: CGRect(x: headX, y: headY, width: headSize, height: headSize))

        // Ear
        ctx.setFillColor(darkColor)
        ctx.fillEllipse(in: CGRect(x: headX + 1, y: headY + headSize - 4, width: 5, height: 6))

        // Eye
        ctx.setFillColor(eyeColor)
        ctx.fillEllipse(in: CGRect(x: headX + 3, y: headY + 5, width: 2.5, height: 2.5))

        // Nose
        ctx.setFillColor(noseColor)
        ctx.fillEllipse(in: CGRect(x: headX - 1, y: headY + 3, width: 3, height: 2.5))

        // Tail (wagging)
        ctx.setStrokeColor(bodyColor)
        ctx.setLineWidth(2.5)
        let tailX = bodyX + bodyW
        let tailY = bodyY + bodyH - 2
        let tailWag: CGFloat = isRunning ? sin(CGFloat(runFrame) * .pi) * 6 : 3
        ctx.move(to: CGPoint(x: tailX, y: tailY))
        ctx.addQuadCurve(
            to: CGPoint(x: tailX + 8, y: tailY + 8 + tailWag),
            control: CGPoint(x: tailX + 4, y: tailY + 12)
        )
        ctx.strokePath()

        // Bone in mouth
        if hasBone {
            drawBoneInMouth(in: ctx, headX: headX, headY: headY)
        }
    }

    private func drawBoneInMouth(in ctx: CGContext, headX: CGFloat, headY: CGFloat) {
        let boneColor = NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor
        let boneX = headX - 8
        let boneY = headY + 2
        let boneW: CGFloat = 12
        let boneH: CGFloat = 4
        let knobR: CGFloat = 2.5

        ctx.setFillColor(boneColor)
        // Shaft
        ctx.fill(CGRect(x: boneX + knobR, y: boneY, width: boneW - knobR * 2, height: boneH))
        // Knobs
        ctx.fillEllipse(in: CGRect(x: boneX, y: boneY - 1, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: boneX, y: boneY + boneH - knobR + 1, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: boneX + boneW - knobR * 2, y: boneY - 1, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: boneX + boneW - knobR * 2, y: boneY + boneH - knobR + 1, width: knobR * 2, height: knobR * 2))
    }
}
