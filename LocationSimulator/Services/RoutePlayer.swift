import Foundation
import CoreLocation
import Combine

/// Manages playback of a `TimedRoute` by interpolating position along the route
/// and streaming locations to the simulated device via `LocationSimService`.
///
/// Playback occurs at a base frequency of 1 Hz, scaled by an optional multiplier
/// (e.g. 2x halves the interval to 0.5 s). The player respects traffic controls
/// by pausing at their coordinates for the configured duration before resuming
/// interpolation.
@MainActor
final class RoutePlayer: ObservableObject {
    enum PlaybackState {
        case idle
        case running
        case paused
        case completed
    }

    // MARK: - Published State

    @Published var state: PlaybackState = .idle
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var progressRatio: Double = 0.0
    @Published var nextTrafficControl: TrafficControl?
    @Published var currentSpeed: Double = 0.0
    @Published var currentCourse: CLLocationDirection = 0.0

    // MARK: - Private State

    private var timedRoute: TimedRoute?
    @Published var playbackMultiplier: Double = 1.0
    private var startTime: Date?
    private var pausedElapsed: TimeInterval = 0
    private var timer: Timer?
    private var trafficControls: [TrafficControl] = []
    private var activeTrafficControl: TrafficControl?
    private var trafficControlPauseEnd: Date?
    private var processedControlIDs: Set<UUID> = []

    private let locationSimService: LocationSimService

    // MARK: - Init

    init(locationSimService: LocationSimService) {
        self.locationSimService = locationSimService
    }

    // MARK: - Playback Controls

    /// Begins playback of the supplied route.
    ///
    /// - Parameters:
    ///   - route: The pre-computed timed route to follow.
    ///   - trafficControls: Optional stops (stop signs, traffic lights) encountered along the route.
    ///   - playbackMultiplier: Speed multiplier (1.0 = realtime). Clamped to a minimum of 0.1x.
    func start(route: TimedRoute, trafficControls: [TrafficControl] = [], playbackMultiplier: Double = 1.0) {
        guard state == .idle || state == .completed else { return }
        self.timedRoute = route
        self.playbackMultiplier = min(max(0.1, playbackMultiplier), 10.0)
        self.state = .running
        self.startTime = Date()
        self.pausedElapsed = 0
        self.progressRatio = 0.0
        self.activeTrafficControl = nil
        self.trafficControlPauseEnd = nil
        self.currentCoordinate = nil
        self.currentSpeed = 0.0
        self.currentCourse = 0.0
        self.processedControlIDs.removeAll()

        // Sort controls by their chronological position along the route so we encounter
        // them in the correct order during playback.
        self.trafficControls = trafficControls.sorted {
            timeAt(coordinate: $0.coordinate, in: route) < timeAt(coordinate: $1.coordinate, in: route)
        }

        updateNextTrafficControl(elapsedSim: 0)

        // Ensure the low-level simulation backend is ready.
        try? locationSimService.startSimulation()

        scheduleNextTick()
    }

    /// Pauses playback, freezing location updates. Resuming continues from the same simulated point.
    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.invalidate()
        timer = nil
        if let startTime = startTime {
            // Accumulate the simulated time elapsed since the last resume/start.
            pausedElapsed += Date().timeIntervalSince(startTime) * playbackMultiplier
        }
    }

    /// Resumes playback from the exact point where it was paused.
    func resume() {
        guard state == .paused else { return }
        state = .running
        startTime = Date()
        scheduleNextTick()
    }

    /// Stops playback entirely, resets all state, and clears the simulated location.
    func stop() {
        state = .idle
        timer?.invalidate()
        timer = nil
        startTime = nil
        pausedElapsed = 0
        progressRatio = 0.0
        currentCoordinate = nil
        currentSpeed = 0.0
        currentCourse = 0.0
        activeTrafficControl = nil
        trafficControlPauseEnd = nil
        nextTrafficControl = nil
        processedControlIDs.removeAll()
        try? locationSimService.clearLocation()
        locationSimService.stopSimulation()
    }

    // MARK: - Tick Engine

    /// Schedules the next timer tick. The interval is scaled by the playback multiplier
    /// so that 2x speed fires every 0.5 s while maintaining a 1 Hz base frequency.
    private func scheduleNextTick() {
        timer?.invalidate()
        let interval = 1.0 / playbackMultiplier
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Core playback tick. Calculates simulated elapsed time, checks for traffic controls,
    /// interpolates the current position, and pushes the coordinate to the device.
    private func tick() {
        guard state == .running, let timedRoute = timedRoute else { return }

        // If we are currently paused at a traffic control, wait until the pause duration expires.
        if let pauseEnd = trafficControlPauseEnd {
            if Date() < pauseEnd {
                scheduleNextTick()
                return
            } else {
                // Pause complete; resume normal playback.
                trafficControlPauseEnd = nil
                activeTrafficControl = nil
            }
        }

        guard let startTime = startTime else { return }
        let elapsedReal = Date().timeIntervalSince(startTime)
        let elapsedSim = pausedElapsed + (elapsedReal * playbackMultiplier)

        // Check whether we have arrived at an unprocessed traffic control.
        // We use a 1-second proximity window so that slight timing jitter does not miss a control.
        if activeTrafficControl == nil {
            for control in trafficControls {
                let controlTime = timeAt(coordinate: control.coordinate, in: timedRoute)
                guard controlTime > 0,
                      abs(elapsedSim - controlTime) < 1.0,
                      !processedControlIDs.contains(control.id) else {
                    continue
                }
                activeTrafficControl = control
                processedControlIDs.insert(control.id)
                // The real-world wait is shortened/lengthened by the playback multiplier
                // so that the simulated trip time increases by exactly `control.duration`.
                trafficControlPauseEnd = Date().addingTimeInterval(control.duration / playbackMultiplier)
                currentSpeed = 0.0
                // Hold the device exactly at the control coordinate during the pause.
                try? locationSimService.setLocation(latitude: control.coordinate.latitude, longitude: control.coordinate.longitude)
                updateNextTrafficControl(elapsedSim: elapsedSim)
                scheduleNextTick()
                return
            }
        }

        // Interpolate the current position along the route based on simulated elapsed time.
        let (coordinate, speed, course, ratio) = interpolate(at: elapsedSim, in: timedRoute)
        self.currentCoordinate = coordinate
        self.currentSpeed = speed
        self.currentCourse = course
        self.progressRatio = ratio

        if let coord = coordinate {
            try? locationSimService.setLocation(latitude: coord.latitude, longitude: coord.longitude)
        }

        // Playback complete.
        if ratio >= 1.0 {
            state = .completed
            timer?.invalidate()
            timer = nil
            return
        }

        updateNextTrafficControl(elapsedSim: elapsedSim)
        scheduleNextTick()
    }

    // MARK: - Interpolation

    /// Interpolates a position, speed, course, and progress ratio for a given elapsed simulation time.
    ///
    /// - Returns: A tuple of `(coordinate, speed, course, progressRatio)`.
    ///   If the route is empty, all values are zero/nil.
    private func interpolate(at elapsed: TimeInterval, in timedRoute: TimedRoute) -> (CLLocationCoordinate2D?, Double, CLLocationDirection, Double) {
        guard !timedRoute.nodes.isEmpty else { return (nil, 0, 0, 0) }

        if elapsed <= 0 {
            let first = timedRoute.nodes[0]
            return (first.coordinate, first.speed, first.course, 0.0)
        }

        if elapsed >= timedRoute.totalDuration {
            let last = timedRoute.nodes[timedRoute.nodes.count - 1]
            return (last.coordinate, 0, last.course, 1.0)
        }

        // Locate the segment bracketing the elapsed time.
        for i in 1..<timedRoute.nodes.count {
            let prev = timedRoute.nodes[i - 1]
            let next = timedRoute.nodes[i]
            if elapsed >= prev.timestamp && elapsed <= next.timestamp {
                let segmentDuration = next.timestamp - prev.timestamp
                let t = segmentDuration > 0 ? (elapsed - prev.timestamp) / segmentDuration : 0

                let lat = prev.coordinate.latitude + t * (next.coordinate.latitude - prev.coordinate.latitude)
                let lon = prev.coordinate.longitude + t * (next.coordinate.longitude - prev.coordinate.longitude)
                let speed = prev.speed + t * (next.speed - prev.speed)

                // Compute the true forward bearing from the interpolated point toward the next node
                // so that the UI always shows a direction aligned with the direction of travel.
                let course = bearing(
                    from: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    to: next.coordinate
                )
                let ratio = elapsed / timedRoute.totalDuration
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), speed, course, ratio)
            }
        }

        let last = timedRoute.nodes[timedRoute.nodes.count - 1]
        return (last.coordinate, 0, last.course, 1.0)
    }

    // MARK: - Helpers

    /// Returns the timestamp of the route node closest to the given coordinate.
    /// This is used to place traffic controls chronologically along the route.
    private func timeAt(coordinate: CLLocationCoordinate2D, in timedRoute: TimedRoute) -> TimeInterval {
        var closestTime: TimeInterval = 0
        var minDistance = CLLocationDistanceMax
        for node in timedRoute.nodes {
            let dist = CLLocation(latitude: node.coordinate.latitude, longitude: node.coordinate.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if dist < minDistance {
                minDistance = dist
                closestTime = node.timestamp
            }
        }
        return closestTime
    }

    /// Updates `nextTrafficControl` to the first unprocessed control that lies ahead of the
    /// current simulated elapsed time.
    private func updateNextTrafficControl(elapsedSim: TimeInterval) {
        guard let timedRoute = timedRoute else {
            nextTrafficControl = nil
            return
        }
        nextTrafficControl = trafficControls.first { control in
            let controlTime = timeAt(coordinate: control.coordinate, in: timedRoute)
            return controlTime > elapsedSim && !processedControlIDs.contains(control.id)
        }
    }

    // MARK: - Debug Overlay Helpers

    /// Returns the current simulated elapsed time in seconds.
    var currentElapsedTime: TimeInterval {
        guard state == .running || state == .paused else { return 0 }
        guard let startTime = startTime else { return pausedElapsed }
        if state == .paused { return pausedElapsed }
        return pausedElapsed + Date().timeIntervalSince(startTime) * playbackMultiplier
    }

    /// Distance in meters to the next route node ahead of the current elapsed time.
    var nextNodeDistance: CLLocationDistance? {
        guard let current = currentCoordinate, let route = timedRoute else { return nil }
        let elapsed = currentElapsedTime
        for node in route.nodes {
            if node.timestamp > elapsed {
                let currentLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
                let nodeLoc = CLLocation(latitude: node.coordinate.latitude, longitude: node.coordinate.longitude)
                return currentLoc.distance(from: nodeLoc)
            }
        }
        return nil
    }

    /// Distance in meters to the next unprocessed traffic control.
    var nextTrafficControlDistance: CLLocationDistance? {
        guard let current = currentCoordinate, let control = nextTrafficControl else { return nil }
        let currentLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let controlLoc = CLLocation(latitude: control.coordinate.latitude, longitude: control.coordinate.longitude)
        return currentLoc.distance(from: controlLoc)
    }

    /// Calculates the haversine initial bearing from `from` to `to` in degrees (0 = north).
    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        let degrees = radiansBearing * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
