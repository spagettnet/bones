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
