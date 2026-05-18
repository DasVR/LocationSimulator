import CoreLocation

actor SpeedProfileEngine {

    /// Computes a TimedRoute from raw OSRM coordinates and a speed profile.
    func computeTimedRoute(
        coordinates: [CLLocationCoordinate2D],
        profile: SpeedProfile,
        gradients: [SpeedGradient] = []
    ) -> TimedRoute {
        guard coordinates.count >= 2 else {
            return TimedRoute(nodes: [], totalDistance: 0, totalDuration: 0, averageSpeed: 0)
        }

        var nodes: [TimedNode] = []
        var totalDistance: CLLocationDistance = 0
        var currentTime: TimeInterval = 0

        // Add first node at t=0
        nodes.append(TimedNode(
            coordinate: coordinates[0],
            timestamp: 0,
            speed: 0,
            course: 0
        ))

        var cumulativeDistance: CLLocationDistance = 0
        let routeLength = totalRouteLength(coordinates: coordinates)

        for i in 1..<coordinates.count {
            let from = coordinates[i - 1]
            let to = coordinates[i]
            let segmentDistance = from.distance(to: to)
            cumulativeDistance += segmentDistance

            // Determine speed at this point along the route
            let ratio = routeLength > 0 ? cumulativeDistance / routeLength : 0
            let speed = speedAt(ratio: ratio, profile: profile, gradients: gradients)

            let segmentDuration = speed > 0 ? segmentDistance / speed : 0
            currentTime += segmentDuration
            totalDistance += segmentDistance

            let course = bearing(from: from, to: to)

            nodes.append(TimedNode(
                coordinate: to,
                timestamp: currentTime,
                speed: speed,
                course: course
            ))
        }

        let averageSpeed = currentTime > 0 ? totalDistance / currentTime : 0

        return TimedRoute(
            nodes: nodes,
            totalDistance: totalDistance,
            totalDuration: currentTime,
            averageSpeed: averageSpeed
        )
    }

    private func speedAt(ratio: Double, profile: SpeedProfile, gradients: [SpeedGradient]) -> Double {
        // Check if ratio falls within any gradient
        for gradient in gradients where gradient.isValid {
            if ratio >= gradient.fromRatio && ratio <= gradient.toRatio {
                return gradient.targetSpeed
            }
        }
        return profile.defaultSpeed
    }

    private func totalRouteLength(coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        var total: CLLocationDistance = 0
        for i in 1..<coordinates.count {
            total += coordinates[i - 1].distance(to: coordinates[i])
        }
        return total
    }

    /// Computes the initial bearing from one coordinate to another using the haversine formula.
    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude.degreesToRadians
        let lat2 = to.latitude.degreesToRadians
        let dLon = (to.longitude - from.longitude).degreesToRadians

        // y = sin(dLon) * cos(lat2)
        // x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let radians = atan2(y, x)
        let degrees = radians.radiansToDegrees
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension CLLocationCoordinate2D {
    /// Returns the geodesic distance to another coordinate using CLLocation for accuracy.
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
