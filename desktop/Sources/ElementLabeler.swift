import AppKit

struct LabeledElement {
    let code: String
    let node: AXElementNode
    let screenFrame: CGRect
}

@MainActor
class ElementLabeler {
    static let shared = ElementLabeler()

    private(set) var labeledElements: [String: LabeledElement] = [:]

    private init() {}

    /// Re-assign 2-letter codes to all interactable elements.
    /// Called from ActiveAppState.refreshTree() every 5s.
    func relabel() {
        let allElements = ActiveAppState.shared.buttons + ActiveAppState.shared.inputFields

        // Filter to elements with valid frames, sort top-to-bottom, left-to-right
        let withFrames = allElements.filter { $0.frame != nil }
        let sorted = withFrames.sorted { a, b in
            let fa = a.frame!, fb = b.frame!
            if abs(fa.origin.y - fb.origin.y) > 10 {
                return fa.origin.y < fb.origin.y
            }
            return fa.origin.x < fb.origin.x
        }

        var newMap: [String: LabeledElement] = [:]
        for (index, node) in sorted.enumerated() {
            guard index < 676 else { break } // AA..ZZ = 676 max
            let code = codeForIndex(index)
            newMap[code] = LabeledElement(code: code, node: node, screenFrame: node.frame!)
        }
        labeledElements = newMap
    }

    func element(forCode code: String) -> LabeledElement? {
        labeledElements[code.uppercased()]
    }

    /// Serialized code map for the Python agent
    func codeMap() -> [[String: Any]] {
        labeledElements.values
            .sorted { $0.code < $1.code }
            .map { elem in
                var entry: [String: Any] = [
                    "code": elem.code,
                    "role": elem.node.role,
                    "frame": [
                        "x": elem.screenFrame.origin.x,
                        "y": elem.screenFrame.origin.y,
                        "w": elem.screenFrame.width,
                        "h": elem.screenFrame.height
                    ]
                ]
                if let label = elem.node.bestLabel {
                    entry["label"] = label
                }
                if let value = elem.node.value {
                    entry["value"] = value
                }
                entry["type"] = elem.node.isButton ? "button" : "input"
                return entry
            }
    }

    private func codeForIndex(_ index: Int) -> String {
        let first = Character(UnicodeScalar(65 + index / 26)!) // A-Z
        let second = Character(UnicodeScalar(65 + index % 26)!) // A-Z
        return String(first) + String(second)
    }
}
