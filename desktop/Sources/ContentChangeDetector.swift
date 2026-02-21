import Foundation
import AppKit

@MainActor
class ContentChangeDetector {
    let windowID: CGWindowID
    var onContentChanged: ((Data) -> Void)?

    private var timer: Timer?
    private var lastHash: Int = 0
    private var enabled = true
    private var debouncing = false

    private let pollInterval: TimeInterval = 3.0
    private let debounceDelay: TimeInterval = 0.5

    init(windowID: CGWindowID) {
        self.windowID = windowID
        BoneLog.log("ContentChangeDetector: initialized for window \(windowID)")
    }

    func start() {
        BoneLog.log("ContentChangeDetector: starting with \(pollInterval)s poll interval")
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.tick()
            }
        }
    }

    func pause() {
        enabled = false
        BoneLog.log("ContentChangeDetector: paused")
    }

    func resume() {
        enabled = true
        BoneLog.log("ContentChangeDetector: resumed")
    }

    func stop() {
        BoneLog.log("ContentChangeDetector: stopped")
        timer?.invalidate()
        timer = nil
        onContentChanged = nil
    }

    private func tick() async {
        guard enabled, !debouncing else { return }

        guard let pixelData = await ScreenshotCapture.captureHashData(windowID: windowID) else {
            return
        }

        let hash = computeHash(pixelData)

        if lastHash == 0 {
            // First capture — just store the baseline
            lastHash = hash
            BoneLog.log("ContentChangeDetector: baseline hash set")
            return
        }

        if hash != lastHash {
            BoneLog.log("ContentChangeDetector: change detected, debouncing...")
            debouncing = true

            // Wait for page to finish rendering
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            // Re-capture to confirm the change is stable
            guard let confirmData = await ScreenshotCapture.captureHashData(windowID: windowID) else {
                debouncing = false
                return
            }
            let confirmHash = computeHash(confirmData)

            guard confirmHash != lastHash else {
                BoneLog.log("ContentChangeDetector: change was transient, ignoring")
                debouncing = false
                return
            }

            lastHash = confirmHash

            guard enabled else {
                BoneLog.log("ContentChangeDetector: paused during debounce, skipping")
                debouncing = false
                return
            }

            BoneLog.log("ContentChangeDetector: confirmed change, capturing full-res screenshot")
            if let fullRes = await ScreenshotCapture.captureToData(windowID: windowID) {
                onContentChanged?(fullRes)
            }

            debouncing = false
        }
    }

    private func computeHash(_ data: Data) -> Int {
        // Simple and fast hash using FNV-1a variant, sampling every 64th byte
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        let stride = max(1, data.count / 1024)  // Sample ~1024 points
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var i = 0
            while i < data.count {
                hash ^= UInt64(base[i])
                hash &*= 1099511628211 // FNV prime
                i += stride
            }
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }
}
