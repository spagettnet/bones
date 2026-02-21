import CoreGraphics
import AppKit

@MainActor
class WindowTracker {
    let windowID: CGWindowID
    let ownerPID: pid_t
    private var timer: Timer?
    private var lastBounds: CGRect

    var onBoundsChanged: ((CGRect) -> Void)?
    var onWindowClosed: (() -> Void)?

    init(windowID: CGWindowID, ownerPID: pid_t, initialBounds: CGRect) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.lastBounds = initialBounds
    }

    func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkWindow()
            }
        }
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    func currentBounds() -> CGRect {
        return lastBounds
    }

    private func checkWindow() {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], windowID
        ) as? [[String: Any]],
        let info = windowList.first,
        let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
        else {
            onWindowClosed?()
            stopTracking()
            return
        }

        guard let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let w = boundsDict["Width"] as? CGFloat,
              let h = boundsDict["Height"] as? CGFloat
        else { return }

        let bounds = CGRect(x: x, y: y, width: w, height: h)
        if bounds != lastBounds {
            lastBounds = bounds
            onBoundsChanged?(bounds)
        }
    }
}
