@testable import LocationSimulator
import XCTest
import CoreLocation

final class GPXTests: XCTestCase {

    private var validGPX: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LocationSimulator" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="37.0" lon="-122.0">
                <time>2024-01-01T00:00:00Z</time>
              </trkpt>
              <trkpt lat="38.0" lon="-121.0">
                <time>2024-01-01T00:00:01Z</time>
              </trkpt>
              <trkpt lat="39.0" lon="-120.0">
                <time>2024-01-01T00:00:02Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
    }

    // MARK: - Parsing

    func testParseValidGPX() throws {
        let data = try XCTUnwrap(validGPX.data(using: .utf8))
        let coords = try GPXParser.parse(data: data)

        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].latitude, 37.0, accuracy: 0.0001)
        XCTAssertEqual(coords[0].longitude, -122.0, accuracy: 0.0001)
        XCTAssertEqual(coords[1].latitude, 38.0, accuracy: 0.0001)
        XCTAssertEqual(coords[1].longitude, -121.0, accuracy: 0.0001)
        XCTAssertEqual(coords[2].latitude, 39.0, accuracy: 0.0001)
        XCTAssertEqual(coords[2].longitude, -120.0, accuracy: 0.0001)
    }

    func testParseWptAndTrkpt() throws {
        let mixedGPX = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="10.0" lon="20.0"></wpt>
          <trkpt lat="30.0" lon="40.0"></trkpt>
        </gpx>
        """
        let data = try XCTUnwrap(mixedGPX.data(using: .utf8))
        let coords = try GPXParser.parse(data: data)
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 10.0, accuracy: 0.0001)
        XCTAssertEqual(coords[1].latitude, 30.0, accuracy: 0.0001)
    }

    // MARK: - Round-trip export & re-parse

    func testExportAndReparse() throws {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 38.0, longitude: -121.0),
            CLLocationCoordinate2D(latitude: 39.0, longitude: -120.0)
        ]
        let gpxString = GPXExporter.export(coordinates: coords)
        let data = try XCTUnwrap(gpxString.data(using: .utf8))
        let reparsed = try GPXParser.parse(data: data)

        XCTAssertEqual(reparsed.count, 3)
        XCTAssertEqual(reparsed[0].latitude, 37.0, accuracy: 0.0001)
        XCTAssertEqual(reparsed[0].longitude, -122.0, accuracy: 0.0001)
        XCTAssertEqual(reparsed[1].latitude, 38.0, accuracy: 0.0001)
        XCTAssertEqual(reparsed[1].longitude, -121.0, accuracy: 0.0001)
        XCTAssertEqual(reparsed[2].latitude, 39.0, accuracy: 0.0001)
        XCTAssertEqual(reparsed[2].longitude, -120.0, accuracy: 0.0001)
    }

    // MARK: - Error handling

    func testMalformedXMLThrowsNoCoordinates() throws {
        let badData = try XCTUnwrap("not xml at all".data(using: .utf8))
        XCTAssertThrowsError(try GPXParser.parse(data: badData)) { error in
            XCTAssertEqual(error as? GPXError, GPXError.noCoordinates)
        }
    }

    func testEmptyGPXThrowsNoCoordinates() throws {
        let emptyGPX = try XCTUnwrap("<gpx></gpx>".data(using: .utf8))
        XCTAssertThrowsError(try GPXParser.parse(data: emptyGPX)) { error in
            XCTAssertEqual(error as? GPXError, GPXError.noCoordinates)
        }
    }

    func testInvalidEncodingThrowsInvalidXML() {
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        XCTAssertThrowsError(try GPXParser.parse(data: invalidData)) { error in
            XCTAssertEqual(error as? GPXError, GPXError.invalidXML)
        }
    }
}
