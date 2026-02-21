import AppKit
import CoreGraphics

@MainActor
class SessionController {
    private var sidebarWindow: SidebarWindow?
    private var chatController: ChatController?
    private var windowTracker: WindowTracker?

    func startSession(windowInfo: WindowInfo) async {
        endSession()

        // Get API key
        guard let apiKey = KeychainHelper.requireAPIKey() else { return }

        // Check accessibility permission (needed for click/type/scroll)
        if !InteractionTools.checkAccessibilityPermission() {
            InteractionTools.requestAccessibilityPermission()
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Bones needs Accessibility permission to interact with windows (click, type, scroll). Grant permission in System Settings > Privacy & Security > Accessibility, then try again."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        // Bring target window to front
        if let app = NSRunningApplication(processIdentifier: windowInfo.ownerPID) {
            app.activate()
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Re-fetch bounds (may have changed after activation)
        let bounds = freshWindowBounds(windowID: windowInfo.windowID) ?? windowInfo.bounds

        // Create components
        let tracker = WindowTracker(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            initialBounds: bounds
        )
        self.windowTracker = tracker

        let context = TargetContext(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            bounds: bounds,
            retinaScale: 2.0
        )

        let controller = ChatController(
            apiKey: apiKey,
            targetContext: context,
            windowTracker: tracker
        )
        self.chatController = controller

        let sidebar = SidebarWindow(
            chatController: controller,
            windowTracker: tracker,
            targetBounds: bounds
        )
        self.sidebarWindow = sidebar

        sidebar.makeKeyAndOrderFront(nil)

        await controller.startWithScreenshot()
    }

    func endSession() {
        sidebarWindow?.close()
        sidebarWindow = nil
        windowTracker?.stopTracking()
        windowTracker = nil
        chatController = nil
    }

    func toggleDebugTab() {
        sidebarWindow?.toggleDebugTab()
    }

    private func freshWindowBounds(windowID: CGWindowID) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], windowID
        ) as? [[String: Any]],
        let info = windowList.first,
        let boundsRef = info[kCGWindowBounds as String]
        else { return nil }

        var bounds = CGRect.zero
        let cfDict = boundsRef as CFTypeRef as! CFDictionary
        guard CGRectMakeWithDictionaryRepresentation(cfDict, &bounds) else { return nil }
        return bounds
    }
}
