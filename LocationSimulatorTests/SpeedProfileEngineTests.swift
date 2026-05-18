@testable import LocationSimulator
import XCTest
import CoreLocation

final class SpeedProfileEngineTests: XCTestCase {
    private var engine: SpeedProfileEngine!

    override func setUp() {
        super.setUp()
        engine = SpeedProfileEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Gradient speed override

    func testGradientZeroYieldsMaxSpeed() async {
        let coords = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0.001, longitude: 0)
        ]
        let gradient = SpeedGradient(fromRatio: 0.0, toRatio: 1.0, targetSpeed: 30.0)
        let route = await engine.computeTimedRoute(
            coordinates: coords,
            profile: .walking,
            gradients: [gradient]
        )

        XCTAssertEqual(route.nodes.count, 2)
        XCTAssertEqual(route.nodes[1].speed, 30.0, accuracy: 0.1)
    }

    func testGradientOneYieldsMinSpeed() async {
        let coords = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0.001, longitude: 0)
        ]
        let gradient = SpeedGradient(fromRatio: 0.0, toRatio: 1.0, targetSpeed: 1.0)
        let route = await engine.computeTimedRoute(
            coordinates: coords,
            profile: .driving,
            gradients: [gradient]
        )

        XCTAssertEqual(route.nodes.count, 2)
        XCTAssertEqual(route.nodes[1].speed, 1.0, accuracy: 0.1)
    }

    func testNoGradientUsesProfileDefaultSpeed() async {
        let coords = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0.001, longitude: 0)
        ]
        let route = await engine.computeTimedRoute(coordinates: coords, profile: .walking)

        XCTAssertEqual(route.nodes.count, 2)
        XCTAssertEqual(route.nodes[1].speed, SpeedProfile.walking.defaultSpeed, accuracy: 0.1)
    }

    // MARK: - Bearing calculation

    func testBearingDueNorth() async {
        let coords = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 1, longitude: 0)
        ]
        let route = await engine.computeTimedRoute(coordinates: coords, profile: .walking)

        XCTAssertEqual(route.nodes.count, 2)
        XCTAssertEqual(route.nodes[1].course, 0.0, accuracy: 0.1)
    }

    func testBearingDueEast() async {
        let coords = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1)
        ]
        let route = await engine.computeTimedRoute(coordinates: coords, profile: .walking)

        XCTAssertEqual(route.nodes.count, 2)
        XCTAssertEqual(route.nodes[1].course, 90.0, accuracy: 0.1)
    }
}
