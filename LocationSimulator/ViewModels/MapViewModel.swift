import Foundation
import CoreLocation
import Observation

/// View model that manages the state of the map, including pins, route geometry,
/// and the current simulated location.
@MainActor
@Observable
class MapViewModel {
    /// Pins placed on the map (start, end, and traffic controls).
    var pins: [MapPin] = []

    /// The decoded polyline coordinates for the current OSRM route.
    var routeCoordinates: [CLLocationCoordinate2D] = []

    /// The coordinate currently being simulated by the route player.
    var simulatedCoordinate: CLLocationCoordinate2D?

    /// Traffic controls placed along the route.
    var trafficControls: [TrafficControl] = []

    /// The computed timed route for playback.
    var timedRoute: TimedRoute?

    /// Error message for routing failures.
    var routingError: String?

    /// Loading state for route generation.
    var isGeneratingRoute = false

    /// Adds a new pin at the given coordinate.
    ///
    /// Ensures only one start pin and one end pin exist at a time by removing
    /// any existing pin of the same type before appending.
    ///
    /// - Parameters:
    ///   - type: The kind of pin to add (start, end, or traffic control).
    ///   - coordinate: The geographic coordinate for the pin.
    func addPin(at type: PinType, coordinate: CLLocationCoordinate2D) {
        if case .start = type {
            pins.removeAll { pin in
                if case .start = pin.type { return true }
                return false
            }
        }
        if case .end = type {
            pins.removeAll { pin in
                if case .end = pin.type { return true }
                return false
            }
        }
        pins.append(MapPin(coordinate: coordinate, type: type))
    }

    /// Removes all pins of a specific type from the map.
    func removePins(ofType type: PinType) {
        switch type {
        case .start:
            pins.removeAll { pin in
                if case .start = pin.type { return true }
                return false
            }
        case .end:
            pins.removeAll { pin in
                if case .end = pin.type { return true }
                return false
            }
        case .trafficControl:
            pins.removeAll { pin in
                if case .trafficControl = pin.type { return true }
                return false
            }
        }
    }

    /// Removes all pins from the map.
    func clearPins() {
        pins.removeAll()
    }

    /// Sets the current route polyline coordinates.
    func setRoute(coordinates: [CLLocationCoordinate2D]) {
        routeCoordinates = coordinates
    }

    /// Generates a route between the start and end pins using OSRM.
    func generateRoute(profile: OSRMProfile = .car) async {
        guard let start = startCoordinate, let end = endCoordinate else {
            routingError = "Drop both a start and end pin to generate a route."
            return
        }
        isGeneratingRoute = true
        routingError = nil
        defer { isGeneratingRoute = false }

        do {
            let service = OSRMRouteService()
            let response = try await service.fetchRoute(from: start, to: end, profile: profile)
            guard let geometry = response.routes.first?.geometry else {
                routingError = "No route geometry found."
                return
            }
            let coords = OSRMRouteService.decodeCoordinates(from: geometry)
            routeCoordinates = coords
            let engine = SpeedProfileEngine()
            timedRoute = await engine.computeTimedRoute(coordinates: coords, profile: .driving)
        } catch {
            routingError = "Route generation failed: \(error.localizedDescription)"
        }
    }

    /// Snaps a coordinate to the nearest point on the current route polyline.
    func snapToRoute(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        guard routeCoordinates.count >= 2 else { return nil }
        var closest = routeCoordinates[0]
        var minDistance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: closest.latitude, longitude: closest.longitude))
        for coord in routeCoordinates {
            let dist = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist < minDistance {
                minDistance = dist
                closest = coord
            }
        }
        return closest
    }

    /// Adds a traffic control snapped to the nearest point on the route.
    func addTrafficControl(at coordinate: CLLocationCoordinate2D, type: TrafficControlType) {
        guard let snapped = snapToRoute(coordinate) else { return }
        let control = TrafficControl(coordinate: snapped, type: type, duration: type.defaultDuration)
        trafficControls.append(control)
        let pin = MapPin(coordinate: snapped, type: .trafficControl(type))
        pins.append(pin)
    }

    /// Clears all traffic controls and their pins.
    func clearTrafficControls() {
        trafficControls.removeAll()
        pins.removeAll { pin in
            if case .trafficControl = pin.type { return true }
            return false
        }
    }

    /// Convenience accessor for the start pin coordinate.
    var startCoordinate: CLLocationCoordinate2D? {
        pins.first { pin in
            if case .start = pin.type { return true }
            return false
        }?.coordinate
    }

    /// Convenience accessor for the end pin coordinate.
    var endCoordinate: CLLocationCoordinate2D? {
        pins.first { pin in
            if case .end = pin.type { return true }
            return false
        }?.coordinate
    }

    /// Updates the coordinate being simulated by the route player.
    func updateSimulatedCoordinate(_ coordinate: CLLocationCoordinate2D?) {
        simulatedCoordinate = coordinate
    }
}
