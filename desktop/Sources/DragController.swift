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

    func beginDrag(from event: NSEvent, statusItem: NSStatusItem, onClickWithoutDrag: (() -> Void)? = nil) {
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
                    let velocity = dragWindow?.skeletonView.physics.currentVelocity() ?? 0
                    soundEngine.playRattleIfNeeded(velocity: velocity)
                }

            case .leftMouseUp:
                if isDragging {
                    handleDrop(at: NSEvent.mouseLocation)
                } else {
                    onClickWithoutDrag?()
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
        ActiveAppState.shared.attach(windowInfo: windowInfo)
        
        // Freeze skeleton before tearing down drag UI.

        BoneLog.log("DragController: handleDrop at \(point), windowInfo bounds=\(windowInfo.bounds)")

        // Freeze the skeleton and get its final pose
        let finalPose = dragWindow?.freezeAndGetPose() ?? SkeletonDefinition.restPose(hangingFrom: point)
        let dragFrame = dragWindow?.frame ?? .zero
        let dropPoint = point

        soundEngine.stop()

        // Clean up drag and highlight windows (keep session controller alive).
        dragWindow?.stopPhysics()
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
