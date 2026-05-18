import Foundation
import CoreLocation

/// Actor-based service for fetching routes from an OSRM-compatible server.
/// Handles rate limiting, caching, and decoding of OSRM v5 responses.
actor OSRMRouteService {
    private let config: Config
    private var lastRequestTime: Date = .distantPast
    private let cache = NSCache<NSString, OSRMRouteResponseWrapper>()

    /// Service configuration loaded from Config.plist.
    struct Config {
        let baseURL: URL
        let rateLimit: TimeInterval

        /// Loads configuration from the main bundle's Config.plist.
        /// Falls back gracefully by throwing `OSRMError.invalidConfig`.
        static func fromPlist() throws -> Config {
            guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let base = plist["OSRMBaseURL"] as? String,
                  let baseURL = URL(string: base),
                  let rateLimit = plist["OSRMRateLimit"] as? TimeInterval else {
                throw OSRMError.invalidConfig
            }
            return Config(baseURL: baseURL, rateLimit: rateLimit)
        }
    }

    /// Wrapper class required because NSCache only stores reference types.
    final class OSRMRouteResponseWrapper {
        let response: OSRMRouteResponse
        init(_ response: OSRMRouteResponse) {
            self.response = response
        }
    }

    /// Errors that can occur during OSRM route fetching.
    enum OSRMError: Error {
        case invalidConfig
        case rateLimited
        case invalidResponse
        case noRoute
        case networkError(underlying: Error)
    }

    /// Creates the service. Requires Config.plist to be present in the main bundle.
    /// - Parameters:
    ///   - baseURL: Optional override for the OSRM server URL. If nil, reads from Config.plist.
    /// - Throws: `OSRMError.invalidConfig` if Config.plist cannot be read and no baseURL is provided.
    init(baseURL: URL? = nil) throws {
        if let baseURL = baseURL {
            let plistConfig = try Config.fromPlist()
            self.config = Config(baseURL: baseURL, rateLimit: plistConfig.rateLimit)
        } else {
            self.config = try Config.fromPlist()
        }
    }

    /// Fetches a route between two coordinates using the specified OSRM profile.
    ///
    /// - Parameters:
    ///   - from: Starting coordinate.
    ///   - to: Destination coordinate.
    ///   - profile: Routing profile (car, bike, foot). Defaults to `.car`.
    /// - Returns: A decoded `OSRMRouteResponse`.
    /// - Throws: `OSRMError` or decoding/network errors.
    func fetchRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: OSRMProfile = .car
    ) async throws -> OSRMRouteResponse {
        // Check in-memory cache first to avoid unnecessary rate-limit delays.
        let cacheKey = "\(from.latitude),\(from.longitude)-\(to.latitude),\(to.longitude)-\(profile.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.response
        }

        // Rate limiting: ensure at least `config.rateLimit` seconds between requests.
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < config.rateLimit {
            let sleepNanoseconds = UInt64((config.rateLimit - elapsed) * 1_000_000_000)
            try await Task.sleep(nanoseconds: sleepNanoseconds)
        }

        // Build the OSRM v5 route URL.
        // Pattern: {baseURL}/route/v1/{profile}/{lon1},{lat1};{lon2},{lat2}?geometries=geojson&overview=full&steps=true&annotations=true
        let coords = "\(from.longitude),\(from.latitude);\(to.longitude),\(to.latitude)"
        let url = config.baseURL
            .appendingPathComponent("route/v1/\(profile.rawValue)/\(coords)")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw OSRMError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "annotations", value: "true")
        ]
        guard let finalURL = components.url else {
            throw OSRMError.invalidResponse
        }

        let request = URLRequest(url: finalURL)

        // Record request time before the network call so failures are also throttled.
        lastRequestTime = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OSRMError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OSRMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            throw OSRMError.rateLimited
        case 400...499:
            throw OSRMError.invalidResponse
        case 500...599:
            throw OSRMError.invalidResponse
        default:
            throw OSRMError.invalidResponse
        }

        let decoded: OSRMRouteResponse
        do {
            decoded = try JSONDecoder().decode(OSRMRouteResponse.self, from: data)
        } catch {
            throw OSRMError.invalidResponse
        }

        guard decoded.code == "Ok" else {
            throw OSRMError.noRoute
        }

        cache.setObject(OSRMRouteResponseWrapper(decoded), forKey: cacheKey)
        return decoded
    }

    /// Decodes a GeoJSON LineString's coordinates into `CLLocationCoordinate2D` values.
    /// OSRM returns coordinates in `[lon, lat]` order; this method maps them correctly
    /// to `CLLocationCoordinate2D(latitude:longitude:)`.
    ///
    /// - Parameter geometry: A `GeoJSONLineString` from an OSRM route.
    /// - Returns: An array of `CLLocationCoordinate2D` in the same order as the geometry.
    static func decodeCoordinates(from geometry: GeoJSONLineString) -> [CLLocationCoordinate2D] {
        geometry.coordinates.map { coords in
            CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
        }
    }
}
