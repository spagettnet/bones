import AppKit

@MainActor
class DragController {
    var dragWindow: DragWindow?
    var highlightWindow: HighlightWindow?
    var isDragging = false
    var currentTargetWindowID: CGWindowID?
    var currentTargetInfo: WindowInfo?
    var sessionController: SessionController?
    private let dragThreshold: CGFloat = 3.0
    private lazy var soundEngine = BoneSoundEngine()
    private var breakAnimation: BoneBreakAnimation?

    func beginDrag(from event: NSEvent, statusItem: NSStatusItem) {
        guard let buttonWindow = statusItem.button?.window else { return }
        let startPoint = NSEvent.mouseLocation
        isDragging = false

        var keepTracking = true
        while keepTracking {
            guard let nextEvent = buttonWindow.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .keyDown]
            ) else { continue }

            switch nextEvent.type {
            case .leftMouseDragged:
                let currentPoint = NSEvent.mouseLocation
                let distance = hypot(
                    currentPoint.x - startPoint.x,
                    currentPoint.y - startPoint.y
                )

                if !isDragging && distance > dragThreshold {
                    isDragging = true
                    BoneLog.log("DragController: drag threshold crossed, creating DragWindow")
                    dragWindow = DragWindow()
                    highlightWindow = HighlightWindow()
                    dragWindow?.startPhysics()
                    dragWindow?.orderFront(nil)
                }

                if isDragging {
                    dragWindow?.followMouse(at: currentPoint)
                    updateHighlight(at: currentPoint)
                    // Play rattle sound based on bone velocity
                    let velocity = dragWindow?.skeletonView.physics.currentVelocity() ?? 0
                    soundEngine.playRattleIfNeeded(velocity: velocity)
                }

            case .leftMouseUp:
                if isDragging {
                    handleDrop(at: NSEvent.mouseLocation)
                } else {
                    Task { @MainActor in
                        await ScreenshotCapture.captureFullScreen()
                    }
                }
                keepTracking = false

            case .keyDown:
                if nextEvent.keyCode == 53 { // Escape
                    cleanup()
                    keepTracking = false
                }

            default:
                break
            }
        }
    }

    private func updateHighlight(at point: NSPoint) {
        if let windowInfo = WindowDetector.windowAt(point: point) {
            currentTargetWindowID = windowInfo.windowID
            currentTargetInfo = windowInfo
            highlightWindow?.highlight(frame: windowInfo.bounds)
        } else {
            currentTargetWindowID = nil
            currentTargetInfo = nil
            highlightWindow?.orderOut(nil)
        }
    }

    private func handleDrop(at point: NSPoint) {
        guard let windowInfo = currentTargetInfo ?? WindowDetector.windowAt(point: point) else {
            cleanup()
            return
        }

        BoneLog.log("DragController: handleDrop at \(point), windowInfo bounds=\(windowInfo.bounds)")

        // Freeze the skeleton and get its final pose
        let finalPose = dragWindow?.freezeAndGetPose() ?? SkeletonDefinition.restPose(hangingFrom: point)
        let dropPoint = point

        // Stop sound
        soundEngine.stop()

        // Get the drag window's frame so we can convert pose to screen coords
        let dragFrame = dragWindow?.frame ?? .zero

        // Clean up drag and highlight windows
        dragWindow?.close()
        dragWindow = nil
        highlightWindow?.close()
        highlightWindow = nil
        isDragging = false
        currentTargetWindowID = nil
        currentTargetInfo = nil

        // Play break animation, then start session
        let animation = BoneBreakAnimation()
        self.breakAnimation = animation

        BoneLog.log("DragController: starting break animation, dragFrame=\(dragFrame)")
        animation.play(
            fromPose: finalPose,
            dragWindowFrame: dragFrame,
            targetWindowInfo: windowInfo,
            dropPoint: dropPoint
        ) { [weak self] in
            BoneLog.log("DragController: break animation complete, starting session")
            self?.breakAnimation = nil
            Task { @MainActor in
                await self?.sessionController?.startSession(windowInfo: windowInfo)
            }
        }
    }

    private func cleanup() {
        soundEngine.stop()
        dragWindow?.stopPhysics()
        dragWindow?.close()
        dragWindow = nil
        highlightWindow?.close()
        highlightWindow = nil
        breakAnimation?.cancel()
        breakAnimation = nil
        isDragging = false
        currentTargetWindowID = nil
        currentTargetInfo = nil
    }
}
