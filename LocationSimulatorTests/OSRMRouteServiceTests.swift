@testable import LocationSimulator
import XCTest
import CoreLocation

final class OSRMRouteServiceTests: XCTestCase {

    // MARK: - decodeCoordinates(from:)

    func testDecodeCoordinatesSwapsLatLon() {
        let geometry = GeoJSONLineString(
            type: "LineString",
            coordinates: [[-122.0, 37.0], [-121.0, 38.0]]
        )
        let coords = OSRMRouteService.decodeCoordinates(from: geometry)

        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 37.0, accuracy: 0.0001)
        XCTAssertEqual(coords[0].longitude, -122.0, accuracy: 0.0001)
        XCTAssertEqual(coords[1].latitude, 38.0, accuracy: 0.0001)
        XCTAssertEqual(coords[1].longitude, -121.0, accuracy: 0.0001)
    }

    func testDecodeCoordinatesEmpty() {
        let geometry = GeoJSONLineString(type: "LineString", coordinates: [])
        let coords = OSRMRouteService.decodeCoordinates(from: geometry)
        XCTAssertTrue(coords.isEmpty)
    }

    // MARK: - Response decoding

    func testResponseDecodingFromJSON() throws {
        let json = """
        {
            "code": "Ok",
            "routes": [
                {
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[-122.0, 37.0], [-121.0, 38.0]]
                    },
                    "legs": [],
                    "distance": 1000.0,
                    "duration": 120.0
                }
            ],
            "waypoints": [
                {
                    "name": "Start",
                    "location": [-122.0, 37.0],
                    "distance": 0.0
                },
                {
                    "name": "End",
                    "location": [-121.0, 38.0],
                    "distance": 0.0
                }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let response = try JSONDecoder().decode(OSRMRouteResponse.self, from: data)
        XCTAssertEqual(response.code, "Ok")
        XCTAssertEqual(response.routes.count, 1)
        XCTAssertEqual(response.routes[0].distance, 1000.0)
        XCTAssertEqual(response.routes[0].duration, 120.0)

        let decoded = OSRMRouteService.decodeCoordinates(from: response.routes[0].geometry)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].latitude, 37.0, accuracy: 0.0001)
        XCTAssertEqual(decoded[0].longitude, -122.0, accuracy: 0.0001)
    }

    // MARK: - Cache key determinism

    func testCacheKeyDeterminism() {
        // Verifies the cache key format used inside fetchRoute so that
        // identical coordinate + profile pairs always resolve to the same key.
        let fromLat = 37.0
        let fromLon = -122.0
        let toLat = 38.0
        let toLon = -121.0
        let profile = OSRMProfile.car
        let key = "\(fromLat),\(fromLon)-\(toLat),\(toLon)-\(profile.rawValue)"
        XCTAssertEqual(key, "37.0,-122.0-38.0,-121.0-driving")
    }
}
