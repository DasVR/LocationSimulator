import Foundation
import CoreLocation

/// Represents the type of pin that can be placed on the map.
enum PinType {
    case start
    case end
    case trafficControl(TrafficControlType)

    /// Returns `true` if this pin type represents a traffic control.
    var isTrafficControl: Bool {
        if case .trafficControl = self { return true }
        return false
    }
}

/// A pin placed on the map by the user or the routing engine.
struct MapPin: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var type: PinType

    /// Human-readable label for the pin.
    var label: String {
        switch type {
        case .start:
            return "Start"
        case .end:
            return "End"
        case .trafficControl(let controlType):
            return controlType.label
        }
    }
}
