import Foundation
import CoreLocation

enum GPXError: Error {
    case invalidXML
    case noCoordinates
}

struct GPXParser {
    /// Parses a GPX file and extracts waypoint or trackpoint coordinates.
    static func parse(data: Data) throws -> [CLLocationCoordinate2D] {
        guard let xml = String(data: data, encoding: .utf8) else {
            throw GPXError.invalidXML
        }
        var coordinates: [CLLocationCoordinate2D] = []

        // Parse <wpt lat="..." lon="..."> and <trkpt lat="..." lon="...">
        let latPattern = #"lat="([0-9.\-]+)""#
        let lonPattern = #"lon="([0-9.\-]+)""#

        let latRegex = try! NSRegularExpression(pattern: latPattern)
        let lonRegex = try! NSRegularExpression(pattern: lonPattern)

        let wptPattern = #"(<wpt|<trkpt)[^/>]*lat="([0-9.\-]+)"[^/>]*lon="([0-9.\-]+)""#
        let wptRegex = try! NSRegularExpression(pattern: wptPattern, options: .dotMatchesLineSeparators)

        let matches = wptRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 2), in: xml),
                  let lonRange = Range(match.range(at: 3), in: xml),
                  let lat = Double(xml[latRange]),
                  let lon = Double(xml[lonRange]) else { continue }
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        guard !coordinates.isEmpty else {
            throw GPXError.noCoordinates
        }
        return coordinates
    }
}
