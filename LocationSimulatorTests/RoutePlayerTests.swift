@testable import LocationSimulator
import XCTest
import CoreLocation
import Combine

@MainActor
final class RoutePlayerTests: XCTestCase {
    private var player: RoutePlayer!
    private var locationSimService: LocationSimService!

    override func setUp() {
        super.setUp()
        locationSimService = LocationSimService(deviceService: IDeviceService())
        player = RoutePlayer(locationSimService: locationSimService)
    }

    override func tearDown() {
        player.stop()
        player = nil
        locationSimService = nil
        super.tearDown()
    }

    private func makeTimedRoute() -> TimedRoute {
        let nodes = [
            TimedNode(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                timestamp: 0,
                speed: 0,
                course: 0
            ),
            TimedNode(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                timestamp: 10,
                speed: 1,
                course: 90
            )
        ]
        return TimedRoute(
            nodes: nodes,
            totalDistance: 100,
            totalDuration: 10,
            averageSpeed: 10
        )
    }

    // MARK: - Start / stop lifecycle

    func testStartRejectsDoubleStart() {
        let route = makeTimedRoute()
        player.start(route: route)
        XCTAssertEqual(player.state, .running)

        player.start(route: route)
        // Must remain running and not reset
        XCTAssertEqual(player.state, .running)
    }

    func testPlaybackMultiplierClamped() {
        let route = makeTimedRoute()

        player.start(route: route, playbackMultiplier: 0.01)
        XCTAssertEqual(player.playbackMultiplier, 0.1, accuracy: 0.001)

        player.stop()
        player.start(route: route, playbackMultiplier: 100.0)
        XCTAssertEqual(player.playbackMultiplier, 10.0, accuracy: 0.001)
    }

    func testStopTransitionsToIdle() {
        let route = makeTimedRoute()
        player.start(route: route)
        XCTAssertEqual(player.state, .running)

        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.currentCoordinate)
        XCTAssertEqual(player.progressRatio, 0.0)
        XCTAssertEqual(player.currentSpeed, 0.0)
        XCTAssertEqual(player.currentCourse, 0.0)
    }

    // MARK: - Traffic control deduplication

    func testTrafficControlsNotDoubleTriggered() {
        let nodes = [
            TimedNode(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                timestamp: 0,
                speed: 0,
                course: 0
            ),
            TimedNode(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                timestamp: 5,
                speed: 1,
                course: 90
            ),
            TimedNode(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.002),
                timestamp: 10,
                speed: 1,
                course: 90
            )
        ]
        let route = TimedRoute(
            nodes: nodes,
            totalDistance: 200,
            totalDuration: 10,
            averageSpeed: 20
        )
        let control = TrafficControl.stopSign(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            duration: 0.2
        )

        let processedExpectation = expectation(description: "traffic control processed")
        processedExpectation.assertForOverFulfill = true

        var cancellable: AnyCancellable?
        cancellable = player.$nextTrafficControl
            .dropFirst()
            .sink { next in
                if next == nil {
                    processedExpectation.fulfill()
                }
            }

        player.start(route: route, trafficControls: [control], playbackMultiplier: 10.0)
        wait(for: [processedExpectation], timeout: 2.0)
        cancellable?.cancel()

        XCTAssertEqual(player.state, .running)

        // Let additional ticks run to confirm no crash or duplicate processing.
        let stableExpectation = expectation(description: "player remains stable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stableExpectation.fulfill()
        }
        wait(for: [stableExpectation], timeout: 1.0)
        XCTAssertEqual(player.state, .running)
    }
}
