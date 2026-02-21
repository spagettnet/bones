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

            ActiveAppState.shared.recordScreenshot(filename: filename)

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

    /// Capture a window at quarter resolution and return raw pixel data for hashing.
    /// Skips PNG encoding — returns CGImage bitmap data directly. Fast and cheap for comparison.
    static func captureHashData(windowID: CGWindowID) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(scWindow.frame.width) / 4)
            config.height = max(1, Int(scWindow.frame.height) / 4)
            config.captureResolution = .nominal
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            guard let dataProvider = cgImage.dataProvider,
                  let cfData = dataProvider.data else { return nil }
            return cfData as Data
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

    /// Capture a screen region to PNG data. This captures everything visible in that region
    /// including overlays, other windows, etc — unlike captureToData which captures a single window.
    static func captureRegionToData(rect: CGRect) async -> Data? {
        do {
            guard let mainDisplay = NSScreen.main else { return nil }

            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.displayID == mainDisplay.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            }) else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(mainDisplay.frame.width) * 2
            config.height = Int(mainDisplay.frame.height) * 2
            config.captureResolution = .best
            config.showsCursor = false
            // Capture a specific region
            config.sourceRect = rect
            config.width = Int(rect.width) * 2
            config.height = Int(rect.height) * 2

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            let nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: rect.width, height: rect.height)
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

    /// Annotate an image with numbered labels on interactive elements.
    /// Returns the annotated PNG data and a legend mapping numbers to labels.
    static func annotateWithLabels(imageData: Data, elements: [AXElementNode], windowBounds: CGRect, retinaScale: CGFloat) -> (data: Data, legend: String)? {
        guard let nsImage = NSImage(data: imageData) else { return nil }

        let imageSize = nsImage.size
        let newImage = NSImage(size: imageSize)
        newImage.lockFocus()

        // Draw original image
        nsImage.draw(in: NSRect(origin: .zero, size: imageSize))

        // Draw labels on each element
        var legend: [String] = []
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .bold)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]

        for (index, element) in elements.enumerated() {
            guard let frame = element.frame else { continue }
            let label = element.title ?? element.description ?? element.roleDescription ?? element.role
            let number = index + 1

            // Convert screen coords to image coords
            let imgX = (frame.origin.x - windowBounds.origin.x) * retinaScale
            let imgY = (frame.origin.y - windowBounds.origin.y) * retinaScale
            let imgW = frame.width * retinaScale
            let imgH = frame.height * retinaScale

            // Flip Y for AppKit drawing (image coords are top-left, AppKit is bottom-left)
            let flippedY = imageSize.height - imgY - imgH

            // Draw semi-transparent highlight rectangle
            let highlightRect = NSRect(x: imgX, y: flippedY, width: imgW, height: imgH)
            let highlightColor = element.isButton ? NSColor.systemBlue.withAlphaComponent(0.2) : NSColor.systemGreen.withAlphaComponent(0.2)
            highlightColor.setFill()
            NSBezierPath(rect: highlightRect).fill()

            // Draw border
            let borderColor = element.isButton ? NSColor.systemBlue.withAlphaComponent(0.7) : NSColor.systemGreen.withAlphaComponent(0.7)
            borderColor.setStroke()
            let borderPath = NSBezierPath(rect: highlightRect)
            borderPath.lineWidth = 2
            borderPath.stroke()

            // Draw number badge in top-left corner
            let badgeText = "\(number)"
            let textSize = (badgeText as NSString).size(withAttributes: labelAttrs)
            let badgeWidth = textSize.width + 8
            let badgeHeight = textSize.height + 4
            let badgeRect = NSRect(
                x: imgX,
                y: flippedY + imgH - badgeHeight,
                width: badgeWidth,
                height: badgeHeight
            )

            // Badge background
            let badgeColor = element.isButton ? NSColor.systemBlue : NSColor.systemGreen
            badgeColor.setFill()
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3)
            badgePath.fill()

            // Badge text
            (badgeText as NSString).draw(
                at: NSPoint(x: badgeRect.origin.x + 4, y: badgeRect.origin.y + 2),
                withAttributes: labelAttrs
            )

            let elementType = element.isButton ? "button" : "input"
            legend.append("[\(number)] \(elementType): \"\(label)\"")
        }

        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return nil }

        return (data: pngData, legend: legend.joined(separator: "\n"))
    }

    /// Annotate an image with 2-letter Homerow-style codes on each labeled element.
    /// Returns the annotated PNG data and a legend string.
    static func annotateWithCodes(imageData: Data, windowBounds: CGRect, retinaScale: CGFloat) -> (data: Data, legend: String)? {
        guard let nsImage = NSImage(data: imageData) else { return nil }
        let imageSize = nsImage.size
        let newImage = NSImage(size: imageSize)
        newImage.lockFocus()

        nsImage.draw(in: NSRect(origin: .zero, size: imageSize))

        let codeFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.white
        ]

        var legend: [String] = []
        let elements = ElementLabeler.shared.labeledElements.values.sorted { $0.code < $1.code }

        for elem in elements {
            let frame = elem.screenFrame

            // Convert screen coords to image coords
            let imgX = (frame.origin.x - windowBounds.origin.x) * retinaScale
            let imgY = (frame.origin.y - windowBounds.origin.y) * retinaScale
            let imgW = frame.width * retinaScale
            let imgH = frame.height * retinaScale

            // Flip Y for AppKit drawing
            let flippedY = imageSize.height - imgY - imgH

            // Draw subtle border
            let borderColor = elem.node.isButton
                ? NSColor.systemOrange.withAlphaComponent(0.6)
                : NSColor.systemTeal.withAlphaComponent(0.6)
            borderColor.setStroke()
            let borderPath = NSBezierPath(rect: NSRect(x: imgX, y: flippedY, width: imgW, height: imgH))
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // Draw code badge in top-left corner
            let textSize = (elem.code as NSString).size(withAttributes: codeAttrs)
            let badgeW = textSize.width + 6
            let badgeH = textSize.height + 3
            let badgeRect = NSRect(
                x: imgX,
                y: flippedY + imgH - badgeH,
                width: badgeW,
                height: badgeH
            )

            NSColor.systemOrange.setFill()
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3)
            badgePath.fill()

            (elem.code as NSString).draw(
                at: NSPoint(x: badgeRect.origin.x + 3, y: badgeRect.origin.y + 1),
                withAttributes: codeAttrs
            )

            let label = elem.node.bestLabel ?? elem.node.role
            let elementType = elem.node.isButton ? "button" : "input"
            legend.append("[\(elem.code)] \(elementType): \"\(label)\"")
        }

        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return nil }

        return (data: pngData, legend: legend.joined(separator: "\n"))
    }

    /// Compress image data to stay under the Anthropic API 5MB limit.
    /// Returns (data, mediaType) — JPEG if compression needed, original PNG if already small.
    static func compressForAPI(_ imageData: Data) -> (data: Data, mediaType: String) {
        let maxBytes = 4_800_000  // slightly under 5MB to leave headroom

        // If PNG is already small enough, keep it
        if imageData.count <= maxBytes {
            return (data: imageData, mediaType: "image/png")
        }

        guard let nsImage = NSImage(data: imageData) else {
            return (data: imageData, mediaType: "image/png")
        }

        // Try JPEG at decreasing quality levels
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData)
        else {
            return (data: imageData, mediaType: "image/png")
        }

        for quality in [0.7, 0.5, 0.3] {
            if let jpegData = bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ), jpegData.count <= maxBytes {
                BoneLog.log("ScreenshotCapture: compressed \(imageData.count) -> \(jpegData.count) bytes (JPEG q=\(quality))")
                return (data: jpegData, mediaType: "image/jpeg")
            }
        }

        // Still too large — downscale to 50% and try again
        let halfSize = NSSize(width: nsImage.size.width / 2, height: nsImage.size.height / 2)
        let resized = NSImage(size: halfSize)
        resized.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: halfSize),
                     from: NSRect(origin: .zero, size: nsImage.size),
                     operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        if let tiff2 = resized.tiffRepresentation,
           let rep2 = NSBitmapImageRep(data: tiff2),
           let jpegData = rep2.representation(using: .jpeg, properties: [.compressionFactor: 0.6]),
           jpegData.count <= maxBytes {
            BoneLog.log("ScreenshotCapture: downscaled+compressed \(imageData.count) -> \(jpegData.count) bytes")
            return (data: jpegData, mediaType: "image/jpeg")
        }

        // Last resort — return whatever we have
        if let tiff2 = resized.tiffRepresentation,
           let rep2 = NSBitmapImageRep(data: tiff2),
           let jpegData = rep2.representation(using: .jpeg, properties: [.compressionFactor: 0.3]) {
            return (data: jpegData, mediaType: "image/jpeg")
        }

        return (data: imageData, mediaType: "image/png")
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
