import Foundation
import CoreLocation
import Combine

/// Manages background location updates with reference counting to keep the app alive.
///
/// Uses low-accuracy updates (`kCLLocationAccuracyThreeKilometers`) to minimize battery drain.
/// Multiple consumers can call `startKeepAlive()` / `stopKeepAlive()`; the underlying
/// `CLLocationManager` only starts when the first consumer requests it and stops when
/// the last consumer releases it.
@MainActor
final class BackgroundLocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let manager = CLLocationManager()
    private var activityCount = 0

    @Published var isActive = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Increments the keep-alive reference count and starts location updates if this
    /// is the first active consumer.
    func startKeepAlive() {
        activityCount += 1
        if activityCount == 1 {
            manager.startUpdatingLocation()
            isActive = true
        }
    }

    /// Decrements the keep-alive reference count and stops location updates when the
    /// count reaches zero. Prevents underflow by clamping to zero.
    func stopKeepAlive() {
        activityCount -= 1
        if activityCount <= 0 {
            activityCount = 0
            manager.stopUpdatingLocation()
            isActive = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // No-op; we only need the keep-alive side effect
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No-op; background updates may fail when the app is suspended
    }
}
