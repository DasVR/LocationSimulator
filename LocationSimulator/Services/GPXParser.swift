import Foundation
import CoreLocation

enum GPXError: Error {
    case invalidXML
    case noCoordinates
}

struct GPXParser {
    /// Parses a GPX file and extracts waypoint or trackpoint coordinates using Foundation XMLParser.
    static func parse(data: Data) throws -> [CLLocationCoordinate2D] {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw GPXError.invalidXML
        }
        guard !delegate.coordinates.isEmpty else {
            throw GPXError.noCoordinates
        }
        return delegate.coordinates
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var coordinates: [CLLocationCoordinate2D] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "wpt" || elementName == "trkpt" else { return }
        guard let latString = attributeDict["lat"],
              let lonString = attributeDict["lon"],
              let lat = Double(latString),
              let lon = Double(lonString) else { return }
        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
}
