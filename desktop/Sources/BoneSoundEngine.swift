import AVFoundation

/// Programmatic bone rattle sound using AVAudioEngine.
/// Generates short noise bursts that sound like bone clicks/rattles.
@MainActor
class BoneSoundEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var rattleBuffers: [AVAudioPCMBuffer] = []
    private var lastPlayTime: TimeInterval = 0
    private let minInterval: TimeInterval = 0.07
    private var isRunning = false

    init() {
        setupEngine()
        generateRattleBuffers()
    }

    private func setupEngine() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.4
    }

    private func ensureRunning() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            // Silently fail — sound is non-critical
        }
    }

    private func generateRattleBuffers() {
        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Generate 4 slightly different rattle sounds
        for i in 0..<4 {
            let duration: Double = 0.03 + Double(i) * 0.012  // 30-66ms
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            buffer.frameLength = frameCount

            guard let data = buffer.floatChannelData?[0] else { continue }

            // Frequency varies per buffer for variety
            let freq: Float = 2000 + Float(i) * 800

            for frame in 0..<Int(frameCount) {
                let t = Float(frame) / Float(sampleRate)

                // Exponential decay envelope (sharp attack, fast decay)
                let envelope = exp(-t * (40 + Float(i) * 10))

                // Mix of noise and a high tone for "clicky" character
                let noise = Float.random(in: -1...1)
                let tone = sin(2 * .pi * freq * t)

                // Noise-heavy mix with a touch of tone
                let sample = (noise * 0.7 + tone * 0.3) * envelope

                data[frame] = sample
            }

            rattleBuffers.append(buffer)
        }
    }

    /// Play a rattle sound if velocity exceeds threshold and rate limit allows
    func playRattleIfNeeded(velocity: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayTime > minInterval else { return }
        guard velocity > 40 else { return }

        ensureRunning()

        let volume = min(Float(velocity / 400.0), 1.0) * 0.6
        guard let buffer = rattleBuffers.randomElement() else { return }

        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
        lastPlayTime = now
    }

    /// Play a louder scatter/break sound
    func playScatterSound() {
        ensureRunning()

        // Play multiple buffers at once for a "clatter" effect
        playerNode.volume = 0.8
        for buffer in rattleBuffers {
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stop() {
        playerNode.stop()
        if isRunning {
            engine.stop()
            isRunning = false
        }
    }
}
