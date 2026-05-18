import CoreLocation

struct TimedNode {
    let coordinate: CLLocationCoordinate2D
    let timestamp: TimeInterval // seconds from start
    let speed: Double // m/s
    let course: CLLocationDirection // degrees, 0 = north
}

struct TimedRoute {
    let nodes: [TimedNode]
    let totalDistance: CLLocationDistance
    let totalDuration: TimeInterval
    let averageSpeed: Double
}
