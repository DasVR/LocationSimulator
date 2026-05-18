import Foundation
import CoreLocation

struct GPXExporter {
    /// Exports a timed route to GPX format with <time> tags.
    static func export(coordinates: [CLLocationCoordinate2D], startDate: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LocationSimulator" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
        """

        for (index, coord) in coordinates.enumerated() {
            let time = formatter.string(from: startDate.addingTimeInterval(TimeInterval(index)))
            gpx += "      <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\">\n"
            gpx += "        <time>\(time)Z</time>\n"
            gpx += "      </trkpt>\n"
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }
}
