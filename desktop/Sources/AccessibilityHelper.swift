import AppKit
import ApplicationServices

struct AXElementNode {
    let role: String
    let title: String?
    let description: String?
    let roleDescription: String?
    let value: String?
    let subrole: String?
    let frame: CGRect?
    let children: [AXElementNode]

    var summary: String {
        let label = title ?? description ?? roleDescription
        if let label = label, !label.isEmpty {
            return "\(role): \"\(label)\""
        }
        return role
    }

    func treeString(indent: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var line = prefix + summary
        if let frame = frame {
            line += "  (\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height)))"
        }
        var result = line
        for child in children {
            result += "\n" + child.treeString(indent: indent + 1)
        }
        return result
    }

    var isButton: Bool {
        role == "AXButton" || role == "AXPopUpButton" || role == "AXMenuButton" ||
        role == "AXRadioButton" || role == "AXCheckBox" || role == "AXToggle" ||
        role == "AXDisclosureTriangle" || role == "AXMenuItem" || role == "AXLink" ||
        subrole == "AXCloseButton" || subrole == "AXMinimizeButton" || subrole == "AXZoomButton" ||
        subrole == "AXToggle" || subrole == "AXDocumentArticle"
    }

    var isInputField: Bool {
        role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox" ||
        role == "AXSearchField" || role == "AXSecureTextField"
    }

    func collectInteractable() -> (buttons: [AXElementNode], inputs: [AXElementNode]) {
        var buttons: [AXElementNode] = []
        var inputs: [AXElementNode] = []
        collectInteractableRecursive(buttons: &buttons, inputs: &inputs)
        return (buttons, inputs)
    }

    private func collectInteractableRecursive(buttons: inout [AXElementNode], inputs: inout [AXElementNode]) {
        if isButton { buttons.append(self) }
        if isInputField { inputs.append(self) }
        for child in children {
            child.collectInteractableRecursive(buttons: &buttons, inputs: &inputs)
        }
    }
}

@MainActor
enum AccessibilityHelper {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func elementAtPosition(_ point: CGPoint) -> AXElementNode? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.3)

        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef)
        guard result == .success, let element = elementRef else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.3)
        return nodeFromElement(element, includeChildren: false)
    }

    static func findAXWindow(pid: pid_t, matchingBounds bounds: CGRect) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return nil }

        let tolerance: CGFloat = 20

        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.3)
            guard let pos = getPosition(of: window), let size = getSize(of: window) else { continue }

            if abs(pos.x - bounds.origin.x) <= tolerance &&
               abs(pos.y - bounds.origin.y) <= tolerance &&
               abs(size.width - bounds.width) <= tolerance &&
               abs(size.height - bounds.height) <= tolerance {
                return window
            }
        }

        // Fallback: if no bounds match, use the focused or first window
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.3)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &focusedRef) == .success,
               let focused = focusedRef as? Bool, focused {
                return window
            }
        }
        AXUIElementSetMessagingTimeout(windows[0], 0.3)
        return windows[0]
    }

    /// Builds an AX tree. `maxDepth` counts only meaningful nodes — empty structural
    /// containers (AXGroup with no subrole/title/desc) are traversed for free.
    static func buildTree(from element: AXUIElement, maxDepth: Int = 15) -> AXElementNode? {
        AXUIElementSetMessagingTimeout(element, 0.3)
        return buildTreeRecursive(element: element, semanticDepth: 0, maxDepth: maxDepth)
    }

    // MARK: - Private

    // Roles that are pure structural wrappers — don't count toward depth budget
    private static let containerRoles: Set<String> = [
        "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXLayoutItem"
    ]

    private static func buildTreeRecursive(element: AXUIElement, semanticDepth: Int, maxDepth: Int) -> AXElementNode? {
        AXUIElementSetMessagingTimeout(element, 0.3)

        let role = stringAttribute(of: element, attribute: kAXRoleAttribute as CFString) ?? "AXUnknown"
        let subrole = stringAttribute(of: element, attribute: kAXSubroleAttribute as CFString)

        // Determine if this is a plain structural container (no subrole, no title, no desc)
        // These don't count toward depth — they're just wrapper noise from Electron/Chromium
        let isPlainContainer: Bool
        let title: String?
        let desc: String?
        let roleDesc: String?
        let valueStr: String?
        let frame: CGRect?

        if containerRoles.contains(role) && subrole == nil {
            title = stringAttribute(of: element, attribute: kAXTitleAttribute as CFString)
            desc = stringAttribute(of: element, attribute: kAXDescriptionAttribute as CFString)
            if title == nil && desc == nil {
                // Pure structural container — skip all expensive reads, don't count depth
                isPlainContainer = true
                roleDesc = nil
                valueStr = nil
                frame = nil
            } else {
                // Labeled container — meaningful, counts toward depth
                isPlainContainer = false
                roleDesc = stringAttribute(of: element, attribute: kAXRoleDescriptionAttribute as CFString)
                valueStr = nil
                let pos = getPosition(of: element)
                let size = getSize(of: element)
                frame = (pos != nil && size != nil) ? CGRect(origin: pos!, size: size!) : nil
            }
        } else {
            isPlainContainer = false
            title = stringAttribute(of: element, attribute: kAXTitleAttribute as CFString)
            desc = stringAttribute(of: element, attribute: kAXDescriptionAttribute as CFString)
            roleDesc = stringAttribute(of: element, attribute: kAXRoleDescriptionAttribute as CFString)

            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef) == .success,
               let val = valRef {
                let s = String(describing: val)
                valueStr = s.count > 100 ? String(s.prefix(100)) + "..." : s
            } else {
                valueStr = nil
            }

            let pos = getPosition(of: element)
            let size = getSize(of: element)
            frame = (pos != nil && size != nil) ? CGRect(origin: pos!, size: size!) : nil
        }

        let childDepth = isPlainContainer ? semanticDepth : semanticDepth + 1

        var childNodes: [AXElementNode] = []
        if childDepth <= maxDepth {
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                let limit = min(children.count, 50)
                for i in 0..<limit {
                    if let childNode = buildTreeRecursive(element: children[i], semanticDepth: childDepth, maxDepth: maxDepth) {
                        childNodes.append(childNode)
                    }
                }
            }
        }

        return AXElementNode(
            role: role,
            title: title,
            description: desc,
            roleDescription: roleDesc,
            value: valueStr,
            subrole: subrole,
            frame: frame,
            children: childNodes
        )
    }

    private static func nodeFromElement(_ element: AXUIElement, includeChildren: Bool) -> AXElementNode? {
        return buildTreeRecursive(element: element, semanticDepth: 0, maxDepth: includeChildren ? 1 : 0)
    }

    private static func stringAttribute(of element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let str = ref as? String, !str.isEmpty else { return nil }
        return str
    }

    private static func getPosition(of element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(ref as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func getSize(of element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
