import AppKit

/// Stores the API key in a plain file at ~/.config/bones/api-key.
/// The keychain ties items to code signatures which break on every rebuild.
@MainActor
enum KeychainHelper {
    private static var keyFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/bones/api-key"
    }

    static func getAPIKey() -> String? {
        guard let data = FileManager.default.contents(atPath: keyFilePath),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let dir = (keyFilePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return FileManager.default.createFile(atPath: keyFilePath, contents: key.data(using: .utf8))
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        try? FileManager.default.removeItem(atPath: keyFilePath)
        return true
    }

    /// Returns stored key or prompts user. Returns nil if user cancels.
    static func requireAPIKey() -> String? {
        if let key = getAPIKey() {
            return key
        }
        return promptForAPIKey()
    }

    /// Shows a dialog asking for the API key. Returns nil if cancelled.
    @discardableResult
    static func promptForAPIKey() -> String? {
        // LSUIElement apps don't get a menu bar, so Cmd+V won't work
        // unless we provide an Edit menu with paste action.
        let savedMenu = NSApp.mainMenu
        let menuBar = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        menuBar.addItem(editMenuItem)
        NSApp.mainMenu = menuBar

        let alert = NSAlert()
        alert.messageText = "Anthropic API Key Required"
        alert.informativeText = "Enter your API key to enable AI chat.\nGet one at console.anthropic.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "sk-ant-..."
        input.isEditable = true
        input.isSelectable = true
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        NSApp.mainMenu = savedMenu
        guard response == .alertFirstButtonReturn else { return nil }

        let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        setAPIKey(key)
        return key
    }
}
