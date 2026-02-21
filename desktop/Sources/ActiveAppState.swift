import AppKit

@MainActor
class ActiveAppState {
    static let shared = ActiveAppState()

    var activeWindowID: CGWindowID?
    var appName: String = ""
    var windowTitle: String?
    var windowBounds: CGRect = .zero
    var screenshots: [(filename: String, date: Date)] = []
    var ownerPID: pid_t = 0

    // Context tracking
    var mouseLocation: CGPoint = .zero
    var isFocused: Bool = false
    var elementUnderCursor: AXElementNode?
    var contextTree: AXElementNode?
    var buttons: [AXElementNode] = []
    var inputFields: [AXElementNode] = []
    var debugVisible: Bool = false

    var isActive: Bool { activeWindowID != nil }

    private var boundsTimer: Timer?
    private var treeTimer: Timer?
    private var mouseMonitor: Any?
    private var lastElementLookup: CFAbsoluteTime = 0

    private init() {}

    func attach(windowInfo: WindowInfo) {
        if isActive { detach() }
        activeWindowID = windowInfo.windowID
        appName = windowInfo.ownerName
        windowTitle = windowInfo.windowTitle
        windowBounds = windowInfo.bounds
        ownerPID = windowInfo.ownerPID
        screenshots = []
        mouseLocation = NSEvent.mouseLocation.cgPoint
        isFocused = false
        elementUnderCursor = nil
        contextTree = nil
        buttons = []
        inputFields = []

        PersistentHighlightWindow.shared.highlight(frame: windowBounds)
        startBoundsTimer()
        startTreeTimer()
        startMouseMonitor()
    }

    func recordScreenshot(filename: String) {
        screenshots.append((filename: filename, date: Date()))
    }

    func detach() {
        stopBoundsTimer()
        stopTreeTimer()
        stopMouseMonitor()
        activeWindowID = nil
        appName = ""
        windowTitle = nil
        windowBounds = .zero
        ownerPID = 0
        screenshots = []
        mouseLocation = .zero
        isFocused = false
        elementUnderCursor = nil
        contextTree = nil
        buttons = []
        inputFields = []

        InteractableOverlayWindow.shared.hideAll()
        PersistentHighlightWindow.shared.orderOut(nil)
        debugVisible = false
    }

    // MARK: - Mouse Monitor

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { event in
            MainActor.assumeIsolated {
                ActiveAppState.shared.handleMouseMove(event)
            }
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func handleMouseMove(_ event: NSEvent) {
        guard isActive else { return }
        // NSEvent.mouseLocation is in AppKit coords (bottom-left origin)
        // Convert to CG coords (top-left origin) for AX APIs
        guard let screen = NSScreen.screens.first else { return }
        let appKitPoint = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: appKitPoint.x, y: screen.frame.height - appKitPoint.y)
        mouseLocation = cgPoint

        // Throttle element lookup to 5Hz
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastElementLookup >= 0.2 {
            lastElementLookup = now
            elementUnderCursor = AccessibilityHelper.elementAtPosition(cgPoint)
        }
    }

    // MARK: - Bounds Timer (1Hz)

    private func startBoundsTimer() {
        stopBoundsTimer()
        boundsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                ActiveAppState.shared.refreshBounds()
            }
        }
    }

    private func stopBoundsTimer() {
        boundsTimer?.invalidate()
        boundsTimer = nil
    }

    func refreshBounds() {
        guard let windowID = activeWindowID else { return }

        // Update focus state
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        isFocused = frontPID == ownerPID

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  wid == windowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let newBounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            if newBounds != windowBounds {
                windowBounds = newBounds
                PersistentHighlightWindow.shared.highlight(frame: newBounds)
                InteractableOverlayWindow.shared.updateOverlays()
            }

            if let title = info[kCGWindowName as String] as? String, title != windowTitle {
                windowTitle = title
            }
            return
        }

        detach()
    }

    // MARK: - Tree Timer (0.33Hz)

    private func startTreeTimer() {
        stopTreeTimer()
        // Fire immediately once
        refreshTree()
        treeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                ActiveAppState.shared.refreshTree()
            }
        }
    }

    private func stopTreeTimer() {
        treeTimer?.invalidate()
        treeTimer = nil
    }

    private func refreshTree() {
        guard isActive else { return }
        guard let axWindow = AccessibilityHelper.findAXWindow(pid: ownerPID, matchingBounds: windowBounds) else { return }
        contextTree = AccessibilityHelper.buildTree(from: axWindow, maxDepth: 15)

        if let tree = contextTree {
            let interactable = tree.collectInteractable()
            buttons = interactable.buttons
            inputFields = interactable.inputs
        } else {
            buttons = []
            inputFields = []
        }

        InteractableOverlayWindow.shared.updateOverlays()
        ElementLabeler.shared.relabel()
    }
}

// Helper to convert NSPoint to CGPoint (they're the same type alias, but semantically different coords)
extension NSPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
