import CoreGraphics
import AppKit

struct WindowInfo {
    let windowID: CGWindowID
    let ownerName: String
    let ownerPID: pid_t
    let bounds: CGRect  // CG coordinates (top-left origin)
    let windowTitle: String?
}

@MainActor
enum WindowDetector {
    /// Returns the topmost normal window containing the given screen point.
    /// Point is in AppKit coordinates (bottom-left origin).
    static func windowAt(point appKitPoint: NSPoint) -> WindowInfo? {
        guard let screen = NSScreen.screens.first else { return nil }
        let screenHeight = screen.frame.height

        // Convert AppKit (bottom-left) -> CG (top-left)
        let cgPoint = CGPoint(x: appKitPoint.x, y: screenHeight - appKitPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            if bounds.contains(cgPoint) {
                return WindowInfo(
                    windowID: windowID,
                    ownerName: ownerName,
                    ownerPID: ownerPID,
                    bounds: bounds,
                    windowTitle: info[kCGWindowName as String] as? String
                )
            }
        }
        return nil
    }
}
