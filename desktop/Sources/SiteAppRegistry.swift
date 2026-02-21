import AppKit

struct SiteApp {
    let id: String
    let name: String
    let domain: String
    let description: String
    let projectDir: String  // relative to repo root
    let devPort: Int
}

@MainActor
class SiteAppRegistry {
    static let shared = SiteAppRegistry()

    private var runningProcesses: [String: Process] = [:]

    let apps: [SiteApp] = [
        SiteApp(
            id: "partiful-rehearse",
            name: "Party Rehearsal",
            domain: "partiful.com",
            description: "3D party simulation — walk around and chat with AI-powered guests from the event",
            projectDir: "partifulRehearse",
            devPort: 5173
        )
    ]

    private init() {}

    func appsForURL(_ url: String) -> [SiteApp] {
        let lowered = url.lowercased()
        return apps.filter { lowered.contains($0.domain) }
    }

    func launch(appId: String, pageURL: String) async -> ToolResult {
        guard let app = apps.first(where: { $0.id == appId }) else {
            return ToolResult(success: false, message: "Unknown site app: \(appId)")
        }

        // Find repo root (same pattern as AgentBridge)
        let bundlePath = Bundle.main.bundlePath
        let desktopDir = URL(fileURLWithPath: bundlePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let repoRoot = desktopDir.deletingLastPathComponent()
        let projectDir = repoRoot.appendingPathComponent(app.projectDir)

        guard FileManager.default.fileExists(atPath: projectDir.path) else {
            BoneLog.log("SiteAppRegistry: project dir not found: \(projectDir.path)")
            return ToolResult(success: false, message: "Project directory not found: \(app.projectDir)")
        }

        // Kill any existing process for this app
        if let existing = runningProcesses[appId], existing.isRunning {
            BoneLog.log("SiteAppRegistry: stopping existing \(appId)")
            existing.terminate()
        }

        // Check if node_modules exists, run npm install if not
        let nodeModules = projectDir.appendingPathComponent("node_modules")
        if !FileManager.default.fileExists(atPath: nodeModules.path) {
            BoneLog.log("SiteAppRegistry: running npm install in \(app.projectDir)")
            let installProc = Process()
            installProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            installProc.arguments = ["npm", "install"]
            installProc.currentDirectoryURL = projectDir
            installProc.standardOutput = FileHandle.nullDevice
            installProc.standardError = FileHandle.nullDevice
            do {
                try installProc.run()
                installProc.waitUntilExit()
                if installProc.terminationStatus != 0 {
                    return ToolResult(success: false, message: "npm install failed in \(app.projectDir)")
                }
            } catch {
                return ToolResult(success: false, message: "Failed to run npm install: \(error.localizedDescription)")
            }
        }

        // Launch npm run dev as background process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npm", "run", "dev"]
        proc.currentDirectoryURL = projectDir
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            BoneLog.log("SiteAppRegistry: failed to launch dev server: \(error)")
            return ToolResult(success: false, message: "Failed to start dev server: \(error.localizedDescription)")
        }

        runningProcesses[appId] = proc
        BoneLog.log("SiteAppRegistry: launched \(appId) dev server (pid \(proc.processIdentifier))")

        // Poll until the dev server is ready
        let url = "http://localhost:\(app.devPort)"
        var ready = false
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if await checkServerReady(url: url) {
                ready = true
                break
            }
        }

        if !ready {
            BoneLog.log("SiteAppRegistry: dev server didn't start in time")
            return ToolResult(success: false, message: "Dev server didn't start within 10s. Check \(app.projectDir) for errors.")
        }

        // Open in default browser
        if let openURL = URL(string: url) {
            NSWorkspace.shared.open(openURL)
        }

        BoneLog.log("SiteAppRegistry: opened \(url)")
        return ToolResult(success: true, message: "Launched \(app.name) at \(url)")
    }

    private nonisolated func checkServerReady(url: String) async -> Bool {
        guard let requestURL = URL(string: url) else { return false }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                return true
            }
        } catch {}
        return false
    }

    func stopAll() {
        for (id, proc) in runningProcesses {
            if proc.isRunning {
                BoneLog.log("SiteAppRegistry: stopping \(id)")
                proc.terminate()
            }
        }
        runningProcesses.removeAll()
    }
}
