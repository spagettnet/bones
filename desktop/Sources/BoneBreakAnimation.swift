import AppKit
import QuartzCore

/// Animates the skeleton breaking apart into individual bones that scatter
/// and fall to the target window's title bar, then triggers the dog animation.
@MainActor
class BoneBreakAnimation {
    private var overlayWindow: NSWindow?
    private var boneLayers: [(layer: CALayer, boneID: BoneID, velocity: CGPoint, rotation: CGFloat)] = []
    private var animationTimer: Timer?
    private var onComplete: (() -> Void)?
    private var dogAnimation: DogAnimation?
    private var cancelled = false
    private let soundEngine = BoneSoundEngine()

    // Physics
    private let gravity: CGFloat = 1400
    private let bounceRestitution: CGFloat = 0.25
    private let friction: CGFloat = 0.85
    private var floorY: CGFloat = 0  // In overlay-local coords (Y-up)
    private var elapsed: TimeInterval = 0
    private let scatterDuration: TimeInterval = 1.0

    func play(
        fromPose pose: SkeletonPose,
        dragWindowFrame: CGRect,
        targetWindowBounds: CGRect,  // CG coordinates (Y-down from top-left of screen)
        dropPoint: NSPoint,          // AppKit coordinates (Y-up)
        completion: @escaping () -> Void
    ) {
        self.onComplete = completion

        // Convert target bounds from CG coords to AppKit coords
        guard let screen = NSScreen.main else {
            completion()
            return
        }
        let screenHeight = screen.frame.height
        let targetAppKit = CGRect(
            x: targetWindowBounds.origin.x,
            y: screenHeight - targetWindowBounds.origin.y - targetWindowBounds.height,
            width: targetWindowBounds.width,
            height: targetWindowBounds.height
        )

        // Create overlay window covering the area from drop point down to target title bar
        let overlayRect = calculateOverlayRect(
            dropPoint: dropPoint,
            targetFrame: targetAppKit,
            screenFrame: screen.frame
        )

        let window = NSWindow(
            contentRect: overlayRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false

        let rootView = NSView(frame: NSRect(origin: .zero, size: overlayRect.size))
        rootView.wantsLayer = true
        rootView.layer?.isGeometryFlipped = false
        window.contentView = rootView

        self.overlayWindow = window

        // Floor = title bar Y in overlay-local coords
        // Title bar is at the top of the target window in AppKit coords
        let titleBarY = targetAppKit.maxY
        floorY = titleBarY - overlayRect.origin.y

        // Create bone layers from the skeleton pose
        createBoneLayers(pose: pose, dragWindowFrame: dragWindowFrame, overlayOrigin: overlayRect.origin, rootLayer: rootView.layer!)

        // Play scatter sound
        soundEngine.playScatterSound()

        window.orderFront(nil)

        // Start animation timer
        elapsed = 0
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
        dogAnimation?.cancel()
        overlayWindow?.close()
        overlayWindow = nil
        soundEngine.stop()
    }

    private func calculateOverlayRect(dropPoint: NSPoint, targetFrame: CGRect, screenFrame: CGRect) -> CGRect {
        let margin: CGFloat = 100
        let minX = min(dropPoint.x - margin, targetFrame.minX)
        let maxX = max(dropPoint.x + margin, targetFrame.maxX)
        let minY = targetFrame.maxY - 40  // Below the title bar
        let maxY = dropPoint.y + margin

        return CGRect(
            x: max(minX, screenFrame.minX),
            y: max(minY, screenFrame.minY),
            width: min(maxX - minX, screenFrame.width),
            height: min(maxY - minY, screenFrame.height)
        )
    }

    private func createBoneLayers(pose: SkeletonPose, dragWindowFrame: CGRect, overlayOrigin: CGPoint, rootLayer: CALayer) {
        // Map each bone to its midpoint from the pose, converted to screen coords
        let allBones: [(BoneID, JointID, JointID)] = [
            (.skull, .top, .skullBase),
            (.spine1, .skullBase, .shoulder),
            (.spine2, .shoulder, .midSpine),
            (.spine3, .midSpine, .hip),
            (.ribLeft1, .shoulder, .ribLeftEnd1),
            (.ribLeft2, .midSpine, .ribLeftEnd2),
            (.ribLeft3, .midSpine, .ribLeftEnd3),
            (.ribRight1, .shoulder, .ribRightEnd1),
            (.ribRight2, .midSpine, .ribRightEnd2),
            (.ribRight3, .midSpine, .ribRightEnd3),
            (.upperArmLeft, .shoulder, .elbowLeft),
            (.lowerArmLeft, .elbowLeft, .handLeft),
            (.upperArmRight, .shoulder, .elbowRight),
            (.lowerArmRight, .elbowRight, .handRight),
            (.upperLegLeft, .hip, .kneeLeft),
            (.lowerLegLeft, .kneeLeft, .footLeft),
            (.upperLegRight, .hip, .kneeRight),
            (.lowerLegRight, .kneeRight, .footRight),
        ]

        for (boneID, parentJoint, childJoint) in allBones {
            let p1 = pose.position(of: parentJoint)
            let p2 = pose.position(of: childJoint)

            // Pose coords are in drag window local space (Y-down)
            // Convert to AppKit screen coords: add dragWindowFrame origin, flip Y
            let midPoseX = (p1.x + p2.x) / 2
            let midPoseY = (p1.y + p2.y) / 2

            // In the drag window, Y-down, so screen Y = dragFrame.maxY - poseY
            let screenX = dragWindowFrame.origin.x + midPoseX
            let screenY = dragWindowFrame.origin.y + (dragWindowFrame.height - midPoseY)

            // Convert to overlay-local coords
            let localX = screenX - overlayOrigin.x
            let localY = screenY - overlayOrigin.y

            let spriteSize = SkeletonRenderer.spriteSize(for: boneID)
            let image = SkeletonRenderer.boneImage(for: boneID)

            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: spriteSize)
            layer.position = CGPoint(x: localX, y: localY)
            layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            layer.contentsGravity = .resizeAspect
            rootLayer.addSublayer(layer)

            // Random scatter velocity: upward burst + horizontal spread
            let vx = CGFloat.random(in: -250...250)
            let vy = CGFloat.random(in: 200...500)  // Upward in AppKit coords
            let rotationSpeed = CGFloat.random(in: -8...8)

            boneLayers.append((layer: layer, boneID: boneID, velocity: CGPoint(x: vx, y: vy), rotation: rotationSpeed))
        }
    }

    private func tick() {
        guard !cancelled else { return }

        let dt: CGFloat = 1.0 / 60.0
        elapsed += Double(dt)

        var allSettled = true

        for i in 0..<boneLayers.count {
            var item = boneLayers[i]

            // Apply gravity (Y-up in AppKit)
            item.velocity.y -= gravity * dt
            item.velocity.x *= 0.995  // Slight air resistance

            var pos = item.layer.position
            pos.x += item.velocity.x * dt
            pos.y += item.velocity.y * dt

            // Current rotation
            var currentRotation = item.rotation

            // Bounce off floor
            if pos.y <= floorY + 5 {
                pos.y = floorY + 5
                if abs(item.velocity.y) > 20 {
                    item.velocity.y = -item.velocity.y * bounceRestitution
                    item.velocity.x *= friction
                    currentRotation *= 0.5
                    // Play a quiet click on bounce
                    if abs(item.velocity.y) > 50 {
                        soundEngine.playRattleIfNeeded(velocity: abs(item.velocity.y))
                    }
                } else {
                    item.velocity.y = 0
                    item.velocity.x *= 0.9
                    currentRotation *= 0.1
                }
            }

            // Check if settled
            if abs(item.velocity.x) > 2 || abs(item.velocity.y) > 2 || pos.y > floorY + 8 {
                allSettled = false
            }

            item.layer.position = pos

            // Rotate
            let angle = atan2(item.velocity.y, item.velocity.x)
            if abs(item.velocity.x) > 5 || abs(item.velocity.y) > 5 {
                item.layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            }

            item.rotation = currentRotation
            boneLayers[i] = item
        }

        // After scatter duration or all settled, trigger dog
        if elapsed > scatterDuration || allSettled {
            animationTimer?.invalidate()
            animationTimer = nil
            triggerDogAnimation()
        }
    }

    private func triggerDogAnimation() {
        guard !cancelled else { return }
        guard let overlayWindow = overlayWindow else {
            onComplete?()
            return
        }

        // Find the femur (upperLegLeft) position for the dog to pick up
        let femurItem = boneLayers.first { $0.boneID == .upperLegLeft }
        let femurLayer = femurItem?.layer

        // Convert femur position to screen coords
        let overlayOrigin = overlayWindow.frame.origin
        let femurLocalPos = femurLayer?.position ?? CGPoint(x: overlayWindow.frame.width / 2, y: floorY + 5)
        let femurScreenPos = NSPoint(
            x: overlayOrigin.x + femurLocalPos.x,
            y: overlayOrigin.y + femurLocalPos.y
        )

        let dog = DogAnimation()
        self.dogAnimation = dog

        dog.run(
            titleBarY: overlayOrigin.y + floorY,
            screenMinX: overlayWindow.frame.minX,
            screenMaxX: overlayWindow.frame.maxX,
            bonePosition: femurScreenPos,
            onBonePickup: { [weak self] in
                // Hide the femur bone when the dog grabs it
                femurLayer?.isHidden = true
                self?.soundEngine.playRattleIfNeeded(velocity: 200)
            },
            completion: { [weak self] in
                // Clean up everything
                self?.soundEngine.stop()
                self?.overlayWindow?.close()
                self?.overlayWindow = nil
                self?.dogAnimation = nil
                self?.onComplete?()
            }
        )
    }
}
