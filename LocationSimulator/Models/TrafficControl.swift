import CoreLocation

struct TrafficControl: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let type: TrafficControlType
    let duration: TimeInterval

    static func == (lhs: TrafficControl, rhs: TrafficControl) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
        && lhs.coordinate.longitude == rhs.coordinate.longitude
        && lhs.type == rhs.type
        && lhs.duration == rhs.duration
    }

    static func stopSign(coordinate: CLLocationCoordinate2D, duration: TimeInterval = 3) -> TrafficControl {
        TrafficControl(coordinate: coordinate, type: .stopSign(minimumDuration: duration), duration: duration)
    }

    static func trafficLight(coordinate: CLLocationCoordinate2D, averageDuration: TimeInterval = 45, variance: TimeInterval = 15) -> TrafficControl {
        let random = Double.random(in: -variance...variance)
        let duration = max(0, averageDuration + random)
        return TrafficControl(coordinate: coordinate, type: .trafficLight(averageDuration: averageDuration, variance: variance), duration: duration)
    }
}

enum TrafficControlType: Equatable {
    case stopSign(minimumDuration: TimeInterval)
    case trafficLight(averageDuration: TimeInterval, variance: TimeInterval)

    var displayName: String {
        switch self {
        case .stopSign: return "Stop Sign"
        case .trafficLight: return "Traffic Light"
        }
    }

    var color: String {
        switch self {
        case .stopSign: return "red"
        case .trafficLight: return "yellow"
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .stopSign: return 3
        case .trafficLight: return 45
        }
    }

    /// Alias for `displayName` to match `MapPin.label` usage.
    var label: String { displayName }
}
