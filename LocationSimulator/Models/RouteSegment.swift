import CoreLocation

struct RouteSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let distance: CLLocationDistance // meters
    let baseDuration: TimeInterval // seconds from OSRM
    let annotation: RouteAnnotation?
}
