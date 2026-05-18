@testable import LocationSimulator
import XCTest
import CoreLocation

final class ModelsTests: XCTestCase {

    // MARK: - SpeedProfile

    func testSpeedProfileCasesExist() {
        let profiles: [SpeedProfile] = [.walking, .biking, .driving, .custom(speed: 5.0)]
        XCTAssertEqual(profiles.count, 4)
        XCTAssertTrue(SpeedProfile.allCases.contains(.walking))
        XCTAssertTrue(SpeedProfile.allCases.contains(.biking))
        XCTAssertTrue(SpeedProfile.allCases.contains(.driving))
    }

    func testSpeedProfileDefaultSpeeds() {
        XCTAssertEqual(SpeedProfile.walking.defaultSpeed, 1.4, accuracy: 0.01)
        XCTAssertEqual(SpeedProfile.biking.defaultSpeed, 4.2, accuracy: 0.01)
        XCTAssertEqual(SpeedProfile.driving.defaultSpeed, 13.9, accuracy: 0.01)
        XCTAssertEqual(SpeedProfile.custom(speed: 7.5).defaultSpeed, 7.5, accuracy: 0.01)
    }

    func testSpeedProfileDisplayNames() {
        XCTAssertEqual(SpeedProfile.walking.displayName, "Walking")
        XCTAssertEqual(SpeedProfile.biking.displayName, "Biking")
        XCTAssertEqual(SpeedProfile.driving.displayName, "Driving")
        XCTAssertEqual(SpeedProfile.custom(speed: 1.0).displayName, "Custom")
    }

    // MARK: - MapPin

    func testMapPinCreation() {
        let pin = MapPin(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            type: .start
        )
        XCTAssertEqual(pin.coordinate.latitude, 37.0, accuracy: 0.0001)
        XCTAssertEqual(pin.coordinate.longitude, -122.0, accuracy: 0.0001)
        XCTAssertEqual(pin.type, .start)
    }

    func testMapPinLabels() {
        let startPin = MapPin(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), type: .start)
        let endPin = MapPin(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), type: .end)
        let stopPin = MapPin(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), type: .trafficControl(.stopSign))
        let lightPin = MapPin(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), type: .trafficControl(.trafficLight))

        XCTAssertEqual(startPin.label, "Start")
        XCTAssertEqual(endPin.label, "End")
        XCTAssertEqual(stopPin.label, "Stop Sign")
        XCTAssertEqual(lightPin.label, "Traffic Light")
    }

    func testMapPinIdentifiable() {
        let pin1 = MapPin(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0), type: .start)
        let pin2 = MapPin(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0), type: .start)
        XCTAssertNotEqual(pin1.id, pin2.id)
    }

    // MARK: - SpeedGradient

    func testSpeedGradientValidity() {
        let valid = SpeedGradient(fromRatio: 0.0, toRatio: 0.5, targetSpeed: 10.0)
        XCTAssertTrue(valid.isValid)

        let inverted = SpeedGradient(fromRatio: 0.5, toRatio: 0.0, targetSpeed: 10.0)
        XCTAssertFalse(inverted.isValid)

        let outOfBounds = SpeedGradient(fromRatio: -0.1, toRatio: 1.1, targetSpeed: 10.0)
        XCTAssertFalse(outOfBounds.isValid)
    }
}
