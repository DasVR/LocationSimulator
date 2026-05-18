import Foundation
import Combine

/// Coordinates background keep-alive mechanisms (location updates and silent audio).
///
/// `BackgroundOrchestrator` ensures that both `BackgroundLocationManager` and
/// `BackgroundAudioManager` are started and stopped together, preventing partial
/// state leaks that could drain battery or leave orphaned background tasks.
@MainActor
final class BackgroundOrchestrator: ObservableObject {
    @Published var isKeepingAlive = false

    private let locationManager: BackgroundLocationManager
    private let audioManager: BackgroundAudioManager

    init() {
        self.locationManager = BackgroundLocationManager()
        self.audioManager = BackgroundAudioManager()
    }

    init(
        locationManager: BackgroundLocationManager,
        audioManager: BackgroundAudioManager
    ) {
        self.locationManager = locationManager
        self.audioManager = audioManager
    }

    /// Starts both background keep-alive mechanisms.
    ///
    /// - Throws: Errors propagated from `BackgroundAudioManager.startSilence()`.
    func start() throws {
        guard !isKeepingAlive else { return }
        do {
            try audioManager.startSilence()
            locationManager.startKeepAlive()
            isKeepingAlive = true
        } catch {
            audioManager.stopSilence()
            locationManager.stopKeepAlive()
            isKeepingAlive = false
            throw error
        }
    }

    /// Stops both background keep-alive mechanisms.
    func stop() {
        locationManager.stopKeepAlive()
        audioManager.stopSilence()
        isKeepingAlive = false
    }
}
