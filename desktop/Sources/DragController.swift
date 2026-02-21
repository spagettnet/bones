import AppKit

@MainActor
class DragController {
    var dragWindow: DragWindow?
    var highlightWindow: HighlightWindow?
    var isDragging = false
    var currentTargetWindowID: CGWindowID?
    var sessionController: SessionController?
    private let dragThreshold: CGFloat = 3.0

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
                    dragWindow = DragWindow(image: LittleGuyRenderer.dragImage())
                    highlightWindow = HighlightWindow()
                    dragWindow?.orderFront(nil)
                }

                if isDragging {
                    dragWindow?.followMouse(at: currentPoint)
                    updateHighlight(at: currentPoint)
                }

            case .leftMouseUp:
                if isDragging {
                    handleDrop(at: NSEvent.mouseLocation)
                } else {
                    Task { @MainActor in
                        await ScreenshotCapture.captureFullScreen()
                    }
                }
                cleanup()
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
            highlightWindow?.highlight(frame: windowInfo.bounds)
        } else {
            currentTargetWindowID = nil
            highlightWindow?.orderOut(nil)
        }
    }

    private func handleDrop(at point: NSPoint) {
        guard let windowInfo = WindowDetector.windowAt(point: point) else {
            cleanup()
            return
        }
        cleanup()
        Task { @MainActor in
            await sessionController?.startSession(windowInfo: windowInfo)
        }
    }

    private func cleanup() {
        dragWindow?.close()
        dragWindow = nil
        highlightWindow?.close()
        highlightWindow = nil
        isDragging = false
        currentTargetWindowID = nil
    }
}
