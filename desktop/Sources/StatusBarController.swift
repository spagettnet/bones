import AppKit

@MainActor
class ModelSetting {
    static let shared = ModelSetting()

    struct Model {
        let id: String
        let label: String
    }

    static let available: [Model] = [
        Model(id: "claude-opus-4-6", label: "Claude Opus 4.6"),
        Model(id: "claude-opus-4-5", label: "Claude Opus 4.5"),
        Model(id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6"),
    ]

    private let configPath: String

    var currentModelID: String {
        didSet { save() }
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        configPath = "\(home)/.config/bones/model"
        if let saved = try? String(contentsOfFile: configPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            currentModelID = saved
        } else {
            currentModelID = "claude-opus-4-6"
        }
    }

    private func save() {
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? currentModelID.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}

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
            dragController.beginDrag(from: event, statusItem: statusItem) { [weak self] in
                // Called when user clicks without dragging
                self?.showMenu()
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Bones", action: #selector(showAbout), keyEquivalent: "")
            .target = self

        let debugItem = NSMenuItem(title: "Debug Panel", action: #selector(toggleDebugPanel), keyEquivalent: "d")
        debugItem.target = self
        debugItem.state = ActiveAppState.shared.debugVisible ? .on : .off
        debugItem.isEnabled = ActiveAppState.shared.isActive
        menu.addItem(debugItem)

        // Model picker submenu
        let modelMenu = NSMenu()
        for model in ModelSetting.available {
            let item = NSMenuItem(title: model.label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.id
            item.state = model.id == ModelSetting.shared.currentModelID ? .on : .off
            modelMenu.addItem(item)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

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

    @objc private func toggleDebugPanel() {
        sessionController.toggleDebugTab()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Bones"
        alert.informativeText = "Drag the little guy onto any window to screenshot it.\n\nLeft-click + drag: Screenshot a window\nRight-click: This menu"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        if let modelID = sender.representedObject as? String {
            ModelSetting.shared.currentModelID = modelID
            BoneLog.log("StatusBar: model set to \(modelID)")
            // Push to running agent immediately
            sessionController.sendModelUpdate(modelID)
        }
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
