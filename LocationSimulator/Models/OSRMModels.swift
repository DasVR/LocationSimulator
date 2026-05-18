import Foundation
import CoreLocation

/// Supported OSRM routing profiles.
enum OSRMProfile: String, CaseIterable {
    case car = "driving"
    case bike = "cycling"
    case foot = "walking"
}

/// Top-level response wrapper for OSRM v5 route requests.
struct OSRMRouteResponse: Codable {
    let code: String
    let routes: [Route]
    let waypoints: [Waypoint]
}

/// A single route returned by OSRM.
struct Route: Codable {
    let geometry: GeoJSONLineString
    let legs: [Leg]
    /// Total distance in meters.
    let distance: Double
    /// Total duration in seconds.
    let duration: Double
}

/// A leg represents the path between two waypoints.
struct Leg: Codable {
    let steps: [Step]
    let annotation: RouteAnnotation?
    /// Leg distance in meters.
    let distance: Double
    /// Leg duration in seconds.
    let duration: Double
}

/// A single step (maneuver) within a leg.
struct Step: Codable {
    let name: String
    /// Step distance in meters.
    let distance: Double
    /// Step duration in seconds.
    let duration: Double
    let maneuver: Maneuver
}

/// Maneuver details for a step.
struct Maneuver: Codable {
    let type: String
    /// Location in [lon, lat] order.
    let location: [Double]
    let bearingBefore: Double
    let bearingAfter: Double
}

/// Per-leg annotation arrays (distances, durations, speeds per coordinate segment).
struct RouteAnnotation: Codable {
    let distance: [Double]?
    let duration: [Double]?
    let speed: [Double]?
}

/// GeoJSON LineString geometry as returned by OSRM.
struct GeoJSONLineString: Codable {
    let type: String
    /// Array of [lon, lat] coordinate pairs.
    let coordinates: [[Double]]
}

/// A waypoint returned by OSRM (start, end, or via points).
struct Waypoint: Codable {
    let name: String
    /// Location in [lon, lat] order.
    let location: [Double]
    let distance: Double
}
