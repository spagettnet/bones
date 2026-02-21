import ScreenCaptureKit
import AppKit

@MainActor
enum ScreenshotCapture {
    static func capture(windowID: CGWindowID) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                showError("Could not find window for capture.")
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)

            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width) * 2
            config.height = Int(scWindow.frame.height) * 2
            config.captureResolution = .best
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            let nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: scWindow.frame.width, height: scWindow.frame.height)
            )

            // Save to Desktop
            let desktopURL = FileManager.default.urls(
                for: .desktopDirectory, in: .userDomainMask
            ).first!
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let appName = scWindow.owningApplication?.applicationName ?? "Unknown"
            let filename = "Screenshot - \(appName) - \(timestamp).png"
            let fileURL = desktopURL.appendingPathComponent(filename)

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:])
            else {
                showError("Failed to encode screenshot.")
                return
            }
            try pngData.write(to: fileURL)

            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])

            NSSound(named: "Pop")?.play()
            FeedbackWindow.show(message: "Screenshot saved!", detail: filename)

        } catch {
            showError("Screenshot failed: \(error.localizedDescription)")
        }
    }

    /// Capture a window and return PNG data without saving to disk.
    static func captureToData(windowID: CGWindowID) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width) * 2
            config.height = Int(scWindow.frame.height) * 2
            config.captureResolution = .best
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            let nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: scWindow.frame.width, height: scWindow.frame.height)
            )

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:])
            else { return nil }

            return pngData
        } catch {
            return nil
        }
    }

    static func captureFullScreen() async {
        do {
            guard let mainDisplay = NSScreen.main else {
                showError("No main display found.")
                return
            }

            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            guard let display = content.displays.first(where: {
                $0.displayID == mainDisplay.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            }) else {
                showError("Could not find display for capture.")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(mainDisplay.frame.width) * 2
            config.height = Int(mainDisplay.frame.height) * 2
            config.captureResolution = .best
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            let nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: mainDisplay.frame.width, height: mainDisplay.frame.height)
            )

            let desktopURL = FileManager.default.urls(
                for: .desktopDirectory, in: .userDomainMask
            ).first!
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let filename = "Screenshot - Fullscreen - \(timestamp).png"
            let fileURL = desktopURL.appendingPathComponent(filename)

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:])
            else {
                showError("Failed to encode screenshot.")
                return
            }
            try pngData.write(to: fileURL)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])

            NSSound(named: "Pop")?.play()
            FeedbackWindow.show(message: "Screenshot saved!", detail: filename)

        } catch {
            showError("Fullscreen capture failed: \(error.localizedDescription)")
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
