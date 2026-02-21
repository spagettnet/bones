import AppKit

@MainActor
class SkeletonDragView: NSView {
    let physics: SkeletonPhysics
    private var animationTimer: Timer?

    override init(frame: NSRect) {
        let anchor = CGPoint(x: frame.width / 2, y: 15)
        self.physics = SkeletonPhysics(anchorPoint: anchor, canvasSize: frame.size)
        super.init(frame: frame)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Our physics uses Y-down, but NSView draw is Y-up by default.
        // Flip the context so Y increases downward (matches our physics).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        SkeletonRenderer.drawSkeleton(in: ctx, pose: physics.pose)

        ctx.restoreGState()
    }

    func startPhysics() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // Add to .common modes so it fires during event tracking (drag loop)
        RunLoop.current.add(timer, forMode: .common)
        animationTimer = timer
    }

    func stopPhysics() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        physics.step(dt: 1.0 / 60.0)
        setNeedsDisplay(bounds)
    }
}

@MainActor
class DragWindow: NSWindow {
    let skeletonView: SkeletonDragView
    private var lastScreenPosition: NSPoint?

    init() {
        let size = NSSize(width: 120, height: 160)
        let view = SkeletonDragView(frame: NSRect(origin: .zero, size: size))
        self.skeletonView = view

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
        self.hasShadow = false
        self.alphaValue = 1.0
        self.isReleasedWhenClosed = false
        self.contentView = view
    }

    func followMouse(at point: NSPoint) {
        let w = frame.size.width
        let h = frame.size.height

        // Compute screen-space delta for physics inertia
        if let last = lastScreenPosition {
            let screenDx = point.x - last.x
            let screenDy = point.y - last.y
            // Convert to view-local Y-down coords: screen Y-up → view Y-down
            skeletonView.physics.applyWindowDelta(dx: screenDx, dy: -screenDy)
        }
        lastScreenPosition = point

        // Position window so that the anchor point (top center) is at the cursor
        setFrameOrigin(NSPoint(
            x: point.x - w / 2,
            y: point.y - h + 15
        ))

        // The pin point is always at the top-center of the view (in Y-down coords)
        skeletonView.physics.setPinnedPosition(CGPoint(x: w / 2, y: 15))
    }

    func startPhysics() {
        skeletonView.startPhysics()
        BoneLog.log("DragWindow: physics started")
    }

    func stopPhysics() {
        skeletonView.stopPhysics()
    }

    func freezeAndGetPose() -> SkeletonPose {
        skeletonView.stopPhysics()
        BoneLog.log("DragWindow: froze pose with \(skeletonView.physics.pose.jointPositions.count) joints")
        return skeletonView.physics.pose
    }
}
