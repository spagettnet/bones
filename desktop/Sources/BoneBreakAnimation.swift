import AppKit
import QuartzCore

/// Bones scatter onto the target window and track its position.
/// Dog grabs a bone and sits in the top-right corner.
@MainActor
class BoneBreakAnimation {
    private var overlayWindow: NSWindow?
    private var boneLayers: [(layer: CALayer, boneID: BoneID, velocity: CGPoint)] = []
    private var animationTimer: Timer?
    private var trackingTimer: Timer?
    private var onComplete: (() -> Void)?
    private var dogAnimation: DogAnimation?
    private var cancelled = false
    private let soundEngine = BoneSoundEngine()

    // Target window tracking
    private var targetWindowID: CGWindowID = 0
    private var targetWindowBounds: CGRect = .zero  // CG coords
    private var overlayOffset: CGPoint = .zero       // offset from target window origin

    // Physics
    private let gravity: CGFloat = 900
    private let bounceRestitution: CGFloat = 0.2
    private let friction: CGFloat = 0.7
    private var floorY: CGFloat = 0
    private var elapsed: TimeInterval = 0
    private let maxDuration: TimeInterval = 1.5

    func play(
        fromPose pose: SkeletonPose,
        dragWindowFrame: CGRect,
        targetWindowInfo: WindowInfo,
        dropPoint: NSPoint,
        completion: @escaping () -> Void
    ) {
        self.onComplete = completion
        self.targetWindowID = targetWindowInfo.windowID
        self.targetWindowBounds = targetWindowInfo.bounds

        // CG coords use the PRIMARY screen as reference (top-left origin, Y-down).
        // Must always use screens[0] (primary), NOT NSScreen.main (which could be any screen).
        guard let primaryScreen = NSScreen.screens.first else {
            BoneLog.log("BoneBreak: ERROR no screens")
            completion()
            return
        }
        let primaryH = primaryScreen.frame.height

        let targetAppKit = cgRectToAppKit(targetWindowBounds, primaryScreenHeight: primaryH)

        BoneLog.log("BoneBreak: play() drop=\(dropPoint), targetCG=\(targetWindowBounds), targetAppKit=\(targetAppKit), primaryH=\(primaryH)")
        for (i, s) in NSScreen.screens.enumerated() {
            BoneLog.log("BoneBreak: screen[\(i)] frame=\(s.frame)")
        }

        // Overlay matches the target window exactly + extra height above for the drop
        let extraTop = max(dropPoint.y - targetAppKit.maxY + 60, 60)
        let overlayRect = CGRect(
            x: targetAppKit.minX,
            y: targetAppKit.minY,
            width: targetAppKit.width,
            height: targetAppKit.height + extraTop
        )

        // Remember offset from target window for tracking
        overlayOffset = CGPoint(
            x: overlayRect.origin.x - targetAppKit.origin.x,
            y: overlayRect.origin.y - targetAppKit.origin.y
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
        window.contentView = rootView
        self.overlayWindow = window

        // Floor = bottom of target window (overlay starts at target's bottom edge)
        // Small margin so bones don't clip off the edge
        floorY = 15

        BoneLog.log("BoneBreak: overlay=\(overlayRect), floorY=\(floorY)")

        createBoneLayers(
            pose: pose,
            dragWindowFrame: dragWindowFrame,
            overlayOrigin: overlayRect.origin,
            rootLayer: rootView.layer!
        )

        soundEngine.playScatterSound()
        window.orderFront(nil)

        elapsed = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        // Start tracking target window position
        startWindowTracking()
    }

    func cancel() {
        cancelled = true
        animationTimer?.invalidate()
        animationTimer = nil
        trackingTimer?.invalidate()
        trackingTimer = nil
        dogAnimation?.cancel()
        overlayWindow?.close()
        overlayWindow = nil
        soundEngine.stop()
    }

    // MARK: - Helpers

    private func cgRectToAppKit(_ cg: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        return CGRect(
            x: cg.origin.x,
            y: primaryScreenHeight - cg.origin.y - cg.height,
            width: cg.width,
            height: cg.height
        )
    }

    private func currentTargetAppKit() -> CGRect? {
        guard let primaryH = NSScreen.screens.first?.frame.height else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], targetWindowID) as? [[String: Any]],
              let info = windowList.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let w = boundsDict["Width"] as? CGFloat,
              let h = boundsDict["Height"] as? CGFloat
        else { return nil }
        return cgRectToAppKit(CGRect(x: x, y: y, width: w, height: h), primaryScreenHeight: primaryH)
    }

    // MARK: - Window position tracking

    private func startWindowTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWindowPosition() }
        }
    }

    private func updateWindowPosition() {
        guard let targetAppKit = currentTargetAppKit() else { return }

        // Move overlay to follow the target window
        let newOrigin = NSPoint(
            x: targetAppKit.origin.x + overlayOffset.x,
            y: targetAppKit.origin.y + overlayOffset.y
        )
        overlayWindow?.setFrameOrigin(newOrigin)

        // Also update dog if it exists
        dogAnimation?.updateTargetPosition(targetAppKit: targetAppKit)
    }

    // MARK: - Bone creation

    private func createBoneLayers(pose: SkeletonPose, dragWindowFrame: CGRect, overlayOrigin: CGPoint, rootLayer: CALayer) {
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
            let midX = (p1.x + p2.x) / 2
            let midY = (p1.y + p2.y) / 2

            let screenX = dragWindowFrame.origin.x + midX
            let screenY = dragWindowFrame.origin.y + (dragWindowFrame.height - midY)

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

            let vx = CGFloat.random(in: -180...180)
            let vy = CGFloat.random(in: -50...250)

            boneLayers.append((layer: layer, boneID: boneID, velocity: CGPoint(x: vx, y: vy)))
        }

        BoneLog.log("BoneBreak: created \(boneLayers.count) bone layers")
    }

    // MARK: - Physics tick

    private func tick() {
        guard !cancelled else { return }

        let dt: CGFloat = 1.0 / 60.0
        elapsed += Double(dt)
        var allSettled = true

        for i in 0..<boneLayers.count {
            var item = boneLayers[i]

            item.velocity.y -= gravity * dt
            item.velocity.x *= 0.99

            var pos = item.layer.position
            pos.x += item.velocity.x * dt
            pos.y += item.velocity.y * dt

            // Bounce off floor (bottom of target window)
            if pos.y <= floorY {
                pos.y = floorY
                if abs(item.velocity.y) > 15 {
                    item.velocity.y = -item.velocity.y * bounceRestitution
                    item.velocity.x *= friction
                } else {
                    item.velocity.y = 0
                    item.velocity.x *= 0.85
                }
            }

            // Bounce off left/right walls of target window
            let wallMargin: CGFloat = 10
            let overlayWidth = overlayWindow?.frame.width ?? 1500
            if pos.x <= wallMargin {
                pos.x = wallMargin
                item.velocity.x = abs(item.velocity.x) * bounceRestitution
            } else if pos.x >= overlayWidth - wallMargin {
                pos.x = overlayWidth - wallMargin
                item.velocity.x = -abs(item.velocity.x) * bounceRestitution
            }

            if abs(item.velocity.x) > 3 || abs(item.velocity.y) > 3 || pos.y > floorY + 5 {
                allSettled = false
            }

            if abs(item.velocity.x) > 10 || abs(item.velocity.y) > 10 {
                item.layer.transform = CATransform3DMakeRotation(
                    atan2(item.velocity.y, item.velocity.x), 0, 0, 1
                )
            }

            item.layer.position = pos
            boneLayers[i] = item
        }

        if elapsed > maxDuration || allSettled {
            BoneLog.log("BoneBreak: scatter done, triggering dog")
            animationTimer?.invalidate()
            animationTimer = nil
            triggerDogAnimation()
        }
    }

    // MARK: - Dog

    private func triggerDogAnimation() {
        guard !cancelled, let overlayWindow = overlayWindow else {
            finishUp()
            return
        }

        let targetAppKit = currentTargetAppKit() ?? overlayWindow.frame

        let femurItem = boneLayers.first { $0.boneID == .upperLegLeft }
        let femurLayer = femurItem?.layer
        let overlayOrigin = overlayWindow.frame.origin
        let femurLocalPos = femurLayer?.position ?? CGPoint(x: overlayWindow.frame.width / 2, y: floorY)
        let femurScreenPos = NSPoint(
            x: overlayOrigin.x + femurLocalPos.x,
            y: overlayOrigin.y + femurLocalPos.y
        )

        // Dog sits in top-right corner of target window (title bar area)
        // Title bar is ~28pt from the top of the window
        let titleBarScreenY = targetAppKit.maxY - 28
        let sitPos = NSPoint(
            x: targetAppKit.maxX - 50,
            y: titleBarScreenY
        )

        BoneLog.log("BoneBreak: dog titleBarY=\(titleBarScreenY), sitPos=\(sitPos), femur=\(femurScreenPos)")

        let dog = DogAnimation()
        self.dogAnimation = dog

        dog.run(
            titleBarY: femurScreenPos.y,
            screenMinX: overlayWindow.frame.minX,
            screenMaxX: overlayWindow.frame.maxX,
            bonePosition: femurScreenPos,
            sitPosition: sitPos,
            targetAppKitFrame: targetAppKit,
            onBonePickup: { [weak self] in
                femurLayer?.isHidden = true
                self?.soundEngine.playRattleIfNeeded(velocity: 200)
            },
            completion: { [weak self] in
                self?.finishUp()
            }
        )
    }

    private func finishUp() {
        soundEngine.stop()
        trackingTimer?.invalidate()
        trackingTimer = nil

        if let window = overlayWindow {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                window.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { [weak self] in
                    self?.overlayWindow?.close()
                    self?.overlayWindow = nil
                    self?.dogAnimation = nil
                    self?.onComplete?()
                }
            })
        } else {
            onComplete?()
        }
    }
}
