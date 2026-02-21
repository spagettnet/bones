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
        let boundsDict = info[kCGWindowBounds as String]
        else {
            onWindowClosed?()
            stopTracking()
            return
        }

        // Use the canonical API to parse CG rect dictionaries
        var bounds = CGRect.zero
        let cfDict = boundsDict as CFTypeRef as! CFDictionary
        guard CGRectMakeWithDictionaryRepresentation(cfDict, &bounds) else { return }

        if bounds != lastBounds {
            lastBounds = bounds
            onBoundsChanged?(bounds)
        }
    }
}
