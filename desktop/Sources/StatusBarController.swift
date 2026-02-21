import AppKit

@MainActor
class StatusBarController: NSObject {
    let statusItem: NSStatusItem
    let dragController: DragController
    let sessionController: SessionController

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        sessionController = SessionController()
        dragController = DragController()
        super.init()
        dragController.sessionController = sessionController

        if let button = statusItem.button {
            button.image = SkeletonRenderer.menuBarImage()
            button.image?.isTemplate = true
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            button.action = #selector(statusBarAction(_:))
            button.target = self
        }
    }

    @objc func statusBarAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            dragController.beginDrag(from: event, statusItem: statusItem)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Bones", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Set API Key...", action: #selector(setAPIKey), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "End Chat Session", action: #selector(endSession), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Bones"
        alert.informativeText = "Drag the little guy onto any window to screenshot it.\n\nLeft-click + drag: Screenshot a window\nRight-click: This menu"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func setAPIKey() {
        KeychainHelper.promptForAPIKey()
    }

    @objc private func endSession() {
        sessionController.endSession()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
