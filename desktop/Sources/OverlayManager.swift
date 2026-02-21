import AppKit

@MainActor
class OverlayManager {
    private var overlayWindow: OverlayUIWindow?
    var onBridgeAction: ((_ action: String, _ payload: [String: Any], _ callbackId: String) -> Void)?

    func createOverlay(html: String, width: CGFloat, height: CGFloat, position: String?) {
        destroyOverlay()

        let window = OverlayUIWindow(width: width, height: height)
        window.onBridgeMessage = { [weak self] action, payload, callbackId in
            self?.onBridgeAction?(action, payload, callbackId)
        }
        self.overlayWindow = window

        // Position relative to screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            var origin: CGPoint

            switch position {
            case "center":
                origin = CGPoint(
                    x: screenFrame.midX - width / 2,
                    y: screenFrame.midY - height / 2
                )
            case "top-right":
                origin = CGPoint(
                    x: screenFrame.maxX - width - 20,
                    y: screenFrame.maxY - height - 20
                )
            case "bottom-left":
                origin = CGPoint(
                    x: screenFrame.minX + 20,
                    y: screenFrame.minY + 20
                )
            default: // top-left
                origin = CGPoint(
                    x: screenFrame.minX + 20,
                    y: screenFrame.maxY - height - 20
                )
            }
            window.setFrameOrigin(origin)
        }

        window.makeKeyAndOrderFront(nil)
        window.loadHTML(html)
        BoneLog.log("OverlayManager: created overlay \(Int(width))x\(Int(height))")
    }

    func updateOverlay(html: String) {
        guard let window = overlayWindow else { return }
        window.loadHTML(html)
        BoneLog.log("OverlayManager: updated overlay with new HTML")
    }

    func updateOverlayPartial(javascript: String) {
        guard let window = overlayWindow else { return }
        window.evaluateJS(javascript)
        BoneLog.log("OverlayManager: ran partial JS update")
    }

    func destroyOverlay() {
        guard let window = overlayWindow else { return }
        window.close()
        overlayWindow = nil
        BoneLog.log("OverlayManager: destroyed overlay")
    }

    func sendBridgeResponse(callbackId: String, result: Any) {
        guard let window = overlayWindow else { return }
        let jsonData: Data
        if let dict = result as? [String: Any] {
            jsonData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        } else if let str = result as? String {
            // Wrap string in quotes for JS
            let escaped = str.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
                             .replacingOccurrences(of: "\n", with: "\\n")
            jsonData = Data("\"\(escaped)\"".utf8)
        } else {
            jsonData = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("null".utf8)
        }
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "null"
        window.evaluateJS("window.__bonesBridge.resolve('\(callbackId)', \(jsonString))")
    }

    func sendBridgeError(callbackId: String, error: String) {
        guard let window = overlayWindow else { return }
        let escaped = error.replacingOccurrences(of: "'", with: "\\'")
        window.evaluateJS("window.__bonesBridge.reject('\(callbackId)', '\(escaped)')")
    }

    var hasOverlay: Bool {
        overlayWindow != nil
    }

    /// The CGWindowID of the overlay, for capturing it via ScreenCaptureKit
    var overlayWindowID: CGWindowID? {
        guard let window = overlayWindow else { return nil }
        return CGWindowID(window.windowNumber)
    }

    /// The overlay frame in CG screen coordinates (top-left origin)
    var overlayFrame: CGRect? {
        guard let window = overlayWindow, let screen = NSScreen.main else { return nil }
        let appKitFrame = window.frame
        // Convert AppKit coords (bottom-left origin) to CG coords (top-left origin)
        return CGRect(
            x: appKitFrame.origin.x,
            y: screen.frame.height - appKitFrame.origin.y - appKitFrame.height,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
