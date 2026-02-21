import Security
import AppKit

@MainActor
enum KeychainHelper {
    private static let service = "com.bones.app"
    private static let account = "anthropic-api-key"

    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }

        return key
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        // Delete any existing key first
        deleteAPIKey()

        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns stored key or prompts user. Returns nil if user cancels.
    static func requireAPIKey() -> String? {
        if let key = getAPIKey(), !key.isEmpty {
            return key
        }
        return promptForAPIKey()
    }

    /// Shows a dialog asking for the API key. Returns nil if cancelled.
    @discardableResult
    static func promptForAPIKey() -> String? {
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
        guard response == .alertFirstButtonReturn else { return nil }

        let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        setAPIKey(key)
        return key
    }
}
