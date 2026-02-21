import Foundation

struct SavedOverlay {
    let id: String
    let name: String
    let description: String
    let html: String
    let width: Int
    let height: Int
    let position: String?
    let domain: String
}

@MainActor
class SavedOverlayStore {
    static let shared = SavedOverlayStore()

    private let baseDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        baseDir = home.appendingPathComponent(".bones/apps")
    }

    /// Get the context key: domain for browsers, app name for native apps.
    func currentContextKey() -> String? {
        let appName = ActiveAppState.shared.appName
        if AgentBridge.isBrowser(appName) {
            // Extract domain from page URL
            if let url = URL(string: ActiveAppState.shared.pageURL),
               let host = url.host {
                return host
            }
            return nil
        } else {
            // Native app — use app name
            let name = appName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
    }

    /// Save overlay HTML + metadata to disk.
    func save(id: String, name: String, description: String, html: String,
              width: Int, height: Int, position: String?) -> (success: Bool, message: String) {
        guard let key = currentContextKey() else {
            return (false, "Cannot determine current app/domain context")
        }

        let dir = baseDir.appendingPathComponent(key).appendingPathComponent(id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return (false, "Failed to create directory: \(error.localizedDescription)")
        }

        // Write overlay.html
        let htmlFile = dir.appendingPathComponent("overlay.html")
        do {
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Failed to write overlay.html: \(error.localizedDescription)")
        }

        // Write manifest.json
        let now = ISO8601DateFormatter().string(from: Date())
        var manifest: [String: Any] = [
            "name": name,
            "description": description,
            "width": width,
            "height": height,
            "domain": key,
            "appName": ActiveAppState.shared.appName,
            "createdAt": now,
            "updatedAt": now
        ]
        if let position = position {
            manifest["position"] = position
        }

        // Preserve original createdAt if updating
        let manifestFile = dir.appendingPathComponent("manifest.json")
        if let existingData = try? Data(contentsOf: manifestFile),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
           let createdAt = existing["createdAt"] as? String {
            manifest["createdAt"] = createdAt
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestFile, options: .atomic)
        } catch {
            return (false, "Failed to write manifest.json: \(error.localizedDescription)")
        }

        BoneLog.log("SavedOverlayStore: saved '\(name)' (\(id)) for \(key)")
        return (true, "Saved overlay '\(name)' to ~/.bones/apps/\(key)/\(id)/")
    }

    /// List all saved overlays for the current context.
    func list() -> [SavedOverlay] {
        guard let key = currentContextKey() else { return [] }
        return listForKey(key)
    }

    /// List overlays for a specific context key.
    private func listForKey(_ key: String) -> [SavedOverlay] {
        let contextDir = baseDir.appendingPathComponent(key)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: contextDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var overlays: [SavedOverlay] = []
        for entry in entries {
            let manifestFile = entry.appendingPathComponent("manifest.json")
            let htmlFile = entry.appendingPathComponent("overlay.html")
            guard let manifestData = try? Data(contentsOf: manifestFile),
                  let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  let html = try? String(contentsOf: htmlFile, encoding: .utf8)
            else { continue }

            let overlay = SavedOverlay(
                id: entry.lastPathComponent,
                name: manifest["name"] as? String ?? entry.lastPathComponent,
                description: manifest["description"] as? String ?? "",
                html: html,
                width: manifest["width"] as? Int ?? 400,
                height: manifest["height"] as? Int ?? 300,
                position: manifest["position"] as? String,
                domain: key
            )
            overlays.append(overlay)
        }
        return overlays
    }

    /// Load a specific overlay by ID for the current context.
    func load(id: String) -> SavedOverlay? {
        guard let key = currentContextKey() else { return nil }
        let dir = baseDir.appendingPathComponent(key).appendingPathComponent(id)
        let manifestFile = dir.appendingPathComponent("manifest.json")
        let htmlFile = dir.appendingPathComponent("overlay.html")

        guard let manifestData = try? Data(contentsOf: manifestFile),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let html = try? String(contentsOf: htmlFile, encoding: .utf8)
        else { return nil }

        return SavedOverlay(
            id: id,
            name: manifest["name"] as? String ?? id,
            description: manifest["description"] as? String ?? "",
            html: html,
            width: manifest["width"] as? Int ?? 400,
            height: manifest["height"] as? Int ?? 300,
            position: manifest["position"] as? String,
            domain: key
        )
    }
}
