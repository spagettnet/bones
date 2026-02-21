import CoreGraphics
import AppKit

struct TargetContext {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect       // CG coordinates (top-left origin)
    let retinaScale: CGFloat // 2.0 for retina
}

struct ToolResult {
    let success: Bool
    let message: String
}

@MainActor
enum InteractionTools {

    /// Convert Claude's image-pixel coordinate to an absolute CG screen point.
    /// Claude sees the 2x retina image, so we divide by retinaScale to get
    /// window-relative logical points, then add window origin.
    static func screenPoint(fromImageX imageX: Int, imageY: Int, context: TargetContext) -> CGPoint {
        let windowRelX = CGFloat(imageX) / context.retinaScale
        let windowRelY = CGFloat(imageY) / context.retinaScale
        return CGPoint(
            x: context.bounds.origin.x + windowRelX,
            y: context.bounds.origin.y + windowRelY
        )
    }

    static func click(x: Int, y: Int, context: TargetContext) async -> ToolResult {
        let point = screenPoint(fromImageX: x, imageY: y, context: context)
        bringToFront(pid: context.ownerPID)
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: point, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                     mouseCursorPosition: point, mouseButton: .left)
        else {
            return ToolResult(success: false, message: "Failed to create click events")
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 200_000_000)

        return ToolResult(success: true, message: "Clicked at (\(x), \(y))")
    }

    static func typeText(_ text: String, context: TargetContext) async -> ToolResult {
        bringToFront(pid: context.ownerPID)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Put our text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let vKeyCode: UInt16 = 9
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else {
            return ToolResult(success: false, message: "Failed to create keyboard events")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 200_000_000)

        // Restore old clipboard
        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        return ToolResult(success: true, message: "Typed text (\(text.count) chars)")
    }

    static func scroll(x: Int, y: Int, direction: String, amount: Int, context: TargetContext) async -> ToolResult {
        let point = screenPoint(fromImageX: x, imageY: y, context: context)
        bringToFront(pid: context.ownerPID)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Move mouse to position
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                    mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }

        // Scroll
        let scrollAmount = Int32(direction == "up" ? amount : -amount)
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: scrollAmount,
            wheel2: 0,
            wheel3: 0
        ) {
            scrollEvent.post(tap: .cghidEventTap)
        }

        return ToolResult(success: true, message: "Scrolled \(direction) by \(amount)")
    }

    static func keyCombo(keys: [String], context: TargetContext) async -> ToolResult {
        bringToFront(pid: context.ownerPID)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Separate modifiers from the main key
        var flags: CGEventFlags = []
        var mainKeyName: String?

        for key in keys {
            switch key.lowercased() {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "shift":
                flags.insert(.maskShift)
            case "alt", "option":
                flags.insert(.maskAlternate)
            default:
                mainKeyName = key.lowercased()
            }
        }

        guard let keyName = mainKeyName, let keyCode = keyCodeForName(keyName) else {
            return ToolResult(success: false, message: "No valid key found in: \(keys)")
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return ToolResult(success: false, message: "Failed to create keyboard events")
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 200_000_000)
        return ToolResult(success: true, message: "Pressed key combo: \(keys.joined(separator: "+"))")
    }

    private static func keyCodeForName(_ name: String) -> UInt16? {
        let map: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            "return": 36, "enter": 36, "tab": 48, "space": 49,
            "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
            "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
            "f11": 103, "f12": 111,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "forwarddelete": 117, "`": 50
        ]
        return map[name]
    }

    /// Execute JavaScript in the frontmost browser tab via AppleScript.
    /// Works with Safari, Chrome, Arc, and other Chromium browsers.
    static func runJavaScriptInBrowser(js: String, appName: String) async -> ToolResult {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let script: String
        let lowerName = appName.lowercased()

        if lowerName.contains("safari") {
            script = """
            tell application "Safari"
                do JavaScript "\(escaped)" in front document
            end tell
            """
        } else if lowerName.contains("chrome") || lowerName.contains("chromium") || lowerName.contains("arc") || lowerName.contains("brave") || lowerName.contains("edge") || lowerName.contains("vivaldi") {
            let chromeAppName = appName
            script = """
            tell application "\(chromeAppName)"
                execute front window's active tab javascript "\(escaped)"
            end tell
            """
        } else {
            return ToolResult(success: false, message: "Unsupported browser: \(appName). Supported: Safari, Chrome, Arc, Brave, Edge.")
        }

        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        let result = appleScript?.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            return ToolResult(success: false, message: "JS execution failed: \(message)")
        }

        let output = result?.stringValue ?? ""
        return ToolResult(success: true, message: output)
    }

    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func bringToFront(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }
}
