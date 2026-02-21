import AppKit
import QuartzCore

/// Pixel art dog that runs to a bone, grabs it, then sits in the top-right
/// corner of the target window. Tracks window position.
@MainActor
class DogAnimation {
    private var dogWindow: NSWindow?
    private var dogView: DogSpriteView?
    private var animationTimer: Timer?
    private var cancelled = false

    private var phase: Phase = .enteringLeft
    private var dogX: CGFloat = 0
    private var dogY: CGFloat = 0
    private var targetBoneX: CGFloat = 0
    private var sitX: CGFloat = 0
    private var sitY: CGFloat = 0
    // Sit position relative to the target window (for tracking)
    private var sitOffsetFromTarget: CGPoint = .zero
    private var currentTargetFrame: CGRect = .zero

    private var onBonePickup: (() -> Void)?
    private var onComplete: (() -> Void)?
    private var frameCount: Int = 0
    private var pauseTimer: Int = 0

    private let dogSpeed: CGFloat = 350
    private let runToCornerSpeed: CGFloat = 280
    private let dogSize = NSSize(width: 48, height: 32)
    private let pauseFrames: Int = 15

    enum Phase {
        case enteringLeft
        case pausing
        case runningToCorner
        case sitting
    }

    func run(
        titleBarY: CGFloat,
        screenMinX: CGFloat,
        screenMaxX: CGFloat,
        bonePosition: NSPoint,
        sitPosition: NSPoint,
        targetAppKitFrame: CGRect,
        onBonePickup: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.targetBoneX = bonePosition.x
        self.sitX = sitPosition.x
        self.sitY = sitPosition.y
        self.currentTargetFrame = targetAppKitFrame
        self.sitOffsetFromTarget = CGPoint(
            x: sitPosition.x - targetAppKitFrame.origin.x,
            y: sitPosition.y - targetAppKitFrame.origin.y
        )
        self.onBonePickup = onBonePickup
        self.onComplete = completion

        dogX = screenMaxX + 10
        dogY = titleBarY
        phase = .enteringLeft

        BoneLog.log("DogAnim: run() bone=\(bonePosition), sit=\(sitPosition)")

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

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Called by BoneBreakAnimation when the target window moves
    func updateTargetPosition(targetAppKit: CGRect) {
        currentTargetFrame = targetAppKit
        // Update sit position relative to new window position
        sitX = targetAppKit.origin.x + sitOffsetFromTarget.x
        sitY = targetAppKit.origin.y + sitOffsetFromTarget.y
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
            dogView?.isSitting = false
            dogView?.isRunning = true
            dogView?.runFrame = (frameCount / 5) % 2

            if dogX <= targetBoneX {
                dogX = targetBoneX
                phase = .pausing
                pauseTimer = 0
                dogView?.isRunning = false
            }

        case .pausing:
            pauseTimer += 1
            if pauseTimer == 6 {
                onBonePickup?()
                onBonePickup = nil
                dogView?.hasBone = true
            }
            if pauseTimer >= pauseFrames {
                phase = .runningToCorner
                dogView?.isRunning = true
                dogView?.facingLeft = sitX < dogX
            }

        case .runningToCorner:
            let dx = sitX - dogX
            let dy = sitY - dogY
            let dist = hypot(dx, dy)

            if dist < 5 {
                dogX = sitX
                dogY = sitY
                phase = .sitting
                dogView?.isRunning = false
                dogView?.isSitting = true
                dogView?.facingLeft = false

                BoneLog.log("DogAnim: sitting in corner")

                // Stay briefly then complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self, !self.cancelled else { return }
                    BoneLog.log("DogAnim: complete")
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.4
                        self.dogWindow?.animator().alphaValue = 0
                    }, completionHandler: {
                        MainActor.assumeIsolated {
                            self.dogWindow?.close()
                            self.dogWindow = nil
                            self.onComplete?()
                        }
                    })
                }
            } else {
                let speed = runToCornerSpeed * dt
                dogX += (dx / dist) * speed
                dogY += (dy / dist) * speed
                dogView?.facingLeft = dx < 0
                dogView?.runFrame = (frameCount / 5) % 2
            }

        case .sitting:
            // Track window position while sitting
            dogX = sitX
            dogY = sitY
            break
        }

        updateWindowPosition()
        dogView?.setNeedsDisplay(dogView!.bounds)
    }

    private func updateWindowPosition() {
        dogWindow?.setFrameOrigin(NSPoint(
            x: dogX - dogSize.width / 2,
            y: dogY - 5
        ))
    }
}

// MARK: - Pixel Art Dog Sprite

@MainActor
class DogSpriteView: NSView {
    var facingLeft = true
    var isRunning = false
    var isSitting = false
    var runFrame = 0
    var hasBone = false

    private let px: CGFloat = 2.0

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        SkeletonRenderer.drawWithOutline(in: ctx, size: size) { buf in
            if !self.facingLeft {
                buf.translateBy(x: size.width, y: 0)
                buf.scaleBy(x: -1, y: 1)
            }
            if self.isSitting {
                self.drawSittingDog(in: buf)
            } else {
                self.drawRunningDog(in: buf)
            }
        }
    }

    private func drawRunningDog(in ctx: CGContext) {
        let p = px
        let brown = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.15, alpha: 1.0).cgColor
        let dark = NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.05, alpha: 1.0).cgColor
        let black = NSColor.black.cgColor

        let bx: CGFloat = 6
        let by: CGFloat = 4

        // Legs
        ctx.setFillColor(dark)
        if isRunning && runFrame == 0 {
            fill(ctx, x: bx+1, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+3, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+8, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+10, y: by-2, w: 1, h: 2, p: p)
        } else if isRunning {
            fill(ctx, x: bx+2, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+4, y: by-1, w: 1, h: 1, p: p)
            fill(ctx, x: bx+7, y: by-1, w: 1, h: 1, p: p)
            fill(ctx, x: bx+9, y: by-2, w: 1, h: 2, p: p)
        } else {
            fill(ctx, x: bx+2, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+4, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+8, y: by-2, w: 1, h: 2, p: p)
            fill(ctx, x: bx+10, y: by-2, w: 1, h: 2, p: p)
        }

        // Body
        ctx.setFillColor(brown)
        fill(ctx, x: bx, y: by, w: 12, h: 4, p: p)
        fill(ctx, x: bx+1, y: by+4, w: 10, h: 1, p: p)

        // Head
        fill(ctx, x: bx-3, y: by+2, w: 5, h: 4, p: p)
        fill(ctx, x: bx-4, y: by+3, w: 1, h: 2, p: p)

        // Ear
        ctx.setFillColor(dark)
        fill(ctx, x: bx-1, y: by+6, w: 2, h: 2, p: p)

        // Eye
        ctx.setFillColor(black)
        fill(ctx, x: bx-2, y: by+4, w: 1, h: 1, p: p)

        // Nose
        fill(ctx, x: bx-4, y: by+4, w: 1, h: 1, p: p)

        // Tail
        ctx.setFillColor(brown)
        let tailWag: CGFloat = isRunning ? (runFrame == 0 ? 1 : -1) : 0
        fill(ctx, x: bx+12, y: by+4+tailWag, w: 1, h: 2, p: p)
        fill(ctx, x: bx+13, y: by+5+tailWag, w: 1, h: 2, p: p)

        if hasBone { drawBoneInMouth(in: ctx, headX: bx-6, headY: by+2) }
    }

    private func drawSittingDog(in ctx: CGContext) {
        let p = px
        let brown = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.15, alpha: 1.0).cgColor
        let dark = NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.05, alpha: 1.0).cgColor
        let black = NSColor.black.cgColor

        let bx: CGFloat = 6
        let by: CGFloat = 2

        ctx.setFillColor(brown)
        fill(ctx, x: bx, y: by, w: 8, h: 6, p: p)
        fill(ctx, x: bx+1, y: by+6, w: 6, h: 1, p: p)

        ctx.setFillColor(dark)
        fill(ctx, x: bx, y: by-2, w: 1, h: 2, p: p)
        fill(ctx, x: bx+2, y: by-2, w: 1, h: 2, p: p)

        ctx.setFillColor(brown)
        fill(ctx, x: bx-2, y: by+4, w: 5, h: 5, p: p)
        fill(ctx, x: bx-3, y: by+5, w: 1, h: 2, p: p)

        ctx.setFillColor(dark)
        fill(ctx, x: bx, y: by+9, w: 2, h: 2, p: p)

        ctx.setFillColor(black)
        fill(ctx, x: bx-1, y: by+7, w: 1, h: 1, p: p)
        fill(ctx, x: bx-3, y: by+6, w: 1, h: 1, p: p)

        ctx.setFillColor(brown)
        fill(ctx, x: bx+8, y: by+4, w: 1, h: 2, p: p)
        fill(ctx, x: bx+9, y: by+5, w: 1, h: 2, p: p)

        if hasBone { drawBoneInMouth(in: ctx, headX: bx-5, headY: by+4) }
    }

    private func drawBoneInMouth(in ctx: CGContext, headX: CGFloat, headY: CGFloat) {
        ctx.setFillColor(NSColor.white.cgColor)
        let p = px
        fill(ctx, x: headX, y: headY+1, w: 1, h: 2, p: p)
        fill(ctx, x: headX+1, y: headY+1.5, w: 3, h: 1, p: p)
        fill(ctx, x: headX+4, y: headY+1, w: 1, h: 2, p: p)
    }

    private func fill(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, p: CGFloat) {
        ctx.fill(CGRect(
            x: (x * p).rounded(.down),
            y: (y * p).rounded(.down),
            width: (w * p).rounded(.down),
            height: (h * p).rounded(.down)
        ))
    }
}
