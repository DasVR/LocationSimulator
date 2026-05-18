@testable import LocationSimulator
import XCTest
import CoreLocation

final class TrafficControlTests: XCTestCase {

    // MARK: - Equality

    func testEqualityIgnoresUUID() {
        let a = TrafficControl(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            type: .stopSign(minimumDuration: 3),
            duration: 3
        )
        let b = TrafficControl(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            type: .stopSign(minimumDuration: 3),
            duration: 3
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEqualityDifferentCoordinate() {
        let a = TrafficControl(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            type: .stopSign(minimumDuration: 3),
            duration: 3
        )
        let b = TrafficControl(
            coordinate: CLLocationCoordinate2D(latitude: 38.0, longitude: -122.0),
            type: .stopSign(minimumDuration: 3),
            duration: 3
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Factory methods

    func testStopSignUsesMinimumDuration() {
        let control = TrafficControl.stopSign(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            duration: 5
        )
        XCTAssertEqual(control.duration, 5)
        if case .stopSign(let minimumDuration) = control.type {
            XCTAssertEqual(minimumDuration, 5)
        } else {
            XCTFail("Expected stopSign type")
        }
    }

    func testTrafficLightDurationWithinRange() {
        let control = TrafficControl.trafficLight(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            averageDuration: 45,
            variance: 15
        )
        XCTAssertGreaterThanOrEqual(control.duration, 30)
        XCTAssertLessThanOrEqual(control.duration, 60)
        if case .trafficLight(let avg, let var_) = control.type {
            XCTAssertEqual(avg, 45)
            XCTAssertEqual(var_, 15)
        } else {
            XCTFail("Expected trafficLight type")
        }
    }

    func testTrafficLightZeroVarianceIsExact() {
        let control = TrafficControl.trafficLight(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            averageDuration: 30,
            variance: 0
        )
        XCTAssertEqual(control.duration, 30)
    }
}
