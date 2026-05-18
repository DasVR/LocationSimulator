import Foundation
import AVFoundation
import Combine

enum AudioError: Error {
    case formatCreationFailed
}

/// Plays silent audio using `AVAudioEngine` to keep the app alive in the background.
///
/// The audio session is configured with `.mixWithOthers` so that music and podcast apps
/// are not interrupted. A periodic health-check timer recovers playback if another process
/// interrupts the audio session.
@MainActor
final class BackgroundAudioManager: ObservableObject {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var healthCheckTimer: Timer?

    @Published var isActive = false

    /// Starts the silent-audio engine and activates the audio session.
    ///
    /// - Throws: Errors from `AVAudioSession` category configuration, engine start, or format creation.
    func startSilence() throws {
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: .mixWithOthers)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            throw AudioError.formatCreationFailed
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()

        let frameCount: AVAudioFrameCount = 44100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        // Buffer is zero-initialized (silence)

        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()

        self.engine = engine
        self.player = player
        self.isActive = true

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.player else { return }
                if !player.isPlaying {
                    player.scheduleBuffer(buffer, at: nil, options: .loops)
                    player.play()
                }
            }
        }
    }

    /// Stops the silent-audio engine, invalidates the health-check timer, and deactivates
    /// the audio session.
    func stopSilence() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    deinit {
        stopSilence()
    }
}
