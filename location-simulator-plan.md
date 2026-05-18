# Location Simulation App — Implementation Plan

**Project:** iOS Native Location Simulator ("Stick Debug" style)  
**Target:** iOS 17.0+ (SwiftUI MapKit + async CoreLocation)  
**Distribution:** IPA sideloading (AltStore / Sideloadly / Paid Dev Cert)  
**Routing Engine:** OpenStreetMap OSRM API (self-hosted or demo)  

---

## Phase 0: Documentation Discovery

### Allowed APIs (Verified)

| Feature | API / Framework | Version | Source |
|---------|----------------|---------|--------|
| Location updates | `CLLocationManager` + `CLLocationUpdate.liveUpdates()` | iOS 17+ | Apple Docs |
| Location simulation detection | `CLLocationSourceInformation.isSimulatedBySoftware` | iOS 15+ | Apple Docs |
| Map display | SwiftUI `Map`, `Marker`, `MapPolyline` | iOS 17+ | Apple Docs |
| Map camera | `MapCameraPosition` | iOS 17+ | Apple Docs |
| Routing data | OSRM HTTP API `/route/v1/{profile}/{coords}` | v5.x | OSRM GitHub |
| Route geometry | GeoJSON polyline decoding | — | OSRM Docs |
| IPA distribution | AltStore / Sideloadly / paid cert | iOS 9+ | Community guides |

### Anti-Patterns to Avoid

1. **NO system-wide location spoofing**: iOS has no public API to inject fake `CLLocation` objects into `CLLocationManager` for other apps. Any plan claiming to do this on non-jailbroken devices is impossible.
2. **NO `MKDirections` for custom routing**: `MKDirections` uses Apple's hosted service with usage limits and no custom profiles. Use OSRM instead.
3. **NO App Store distribution**: Apps designed for location spoofing will be rejected under Guideline 5.2.3 (fraud/cheating) or 2.3.1 (hidden features). Plan for sideloading only.
4. **NO `CLLocation` initializer abuse**: `CLLocation` has no public init that lets you fully fabricate `sourceInformation` to hide simulation. iOS 15+ exposes `isSimulatedBySoftware` to consuming apps.
5. **NO hardcoded OSRM demo server for production**: `router.project-osrm.org` is rate-limited to ~1 req/s. Production builds must support configurable endpoints.

### Verified Constraints

- **iOS 16+**: Developer Mode is mandatory for sideloading/debugging. Requires device reboot.
- **iOS 17+**: `CLLocationUpdate.liveUpdates()` replaces old delegate patterns; `CLServiceSession` required for always authorization.
- **iOS 18**: `always` authorization only valid while an active `CLServiceSession` is held.
- **Location spoofing detection**: Modern apps (Life360, Pokemon Go, etc.) detect spoofing via `isSimulatedBySoftware`, Wi-Fi/BSSID mismatch, accelerometer inconsistencies, and impossible GPS jumps.

---

## Phase 1: Project Scaffolding & Permissions

### What to Implement

1. Create new iOS project in Xcode (SwiftUI interface, SwiftData if needed for route storage).
2. Configure `Info.plist` with required location usage descriptions:
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `NSLocationTemporaryUsageDescriptionDictionary` (for precise location requests)
3. Add `MapLibre` or MapKit entitlement (MapKit is free, no key needed for native apps).
4. Set up Swift Package Manager dependencies:
   - `MapLibre Native` (optional alternative renderer) OR stay with native MapKit
   - A GeoJSON parsing library (e.g., `GeoJSON.swift` or custom decoder)
   - A networking layer (`URLSession` is sufficient; no need for Alamofire)
5. Create folder structure:
   ```
   Models/
   Views/
   ViewModels/
   Services/
   Networking/
   Utilities/
   ```
6. Add OSRM endpoint configuration to a `Config.plist` or `AppConfig.swift`:
   - `OSRMBaseURL` (default: `https://router.project-osrm.org`)
   - `OSRMRateLimit` (default: 1.0 seconds)

### Documentation References

- Apple Docs: `CLLocationManager` authorization requirements (iOS 18 `CLServiceSession` changes)
- Apple Docs: `Info.plist` location keys
- OSRM Docs: HTTP API endpoint structure (`/route/v1/{profile}/{coordinates}?geometries=geojson`)

### Verification Checklist

- [ ] `xcodebuild -scheme <YourApp>` compiles without errors.
- [ ] `Info.plist` contains all three location description keys.
- [ ] `Config.plist` is accessible and parses correctly at runtime.
- [ ] App requests location authorization on first launch.

### Anti-Pattern Guards

- Do NOT request `always` authorization without a foreground `CLServiceSession` (iOS 18 requirement).
- Do NOT embed OSRM demo URL as a hardcoded constant in source; use `Config.plist`.
- Do NOT add unnecessary third-party networking libraries.

---

## Phase 2: Map UI with SwiftUI MapKit

### What to Implement

1. **Main Map View** (`MapView.swift`):
   - Use SwiftUI `Map(position:)` with `@State var cameraPosition: MapCameraPosition`.
   - Bind camera to `.userLocation(fallback: .automatic)` for initial centering.
   - Add `.mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }`.
   - Set style: `.mapStyle(.standard(elevation: .realistic, showsTraffic: true))`.

2. **Pin Drop System**:
   - `Marker(coordinate:label:)` for start/end pins.
   - `Annotation` for custom pin UI (if needed for color-coding).
   - Implement tap-to-drop: use `onTapGesture` with `convert(_:to:)` from `MKMapView` proxy if using UIKit bridge, or use `MapReader` (iOS 17+) to convert screen points to coordinates.
   - Store pins in a `@State` array of a custom `MapPin` struct (conforming to `Identifiable`).

3. **Route Polyline Display**:
   - `MapPolyline(_ coordinates: [CLLocationCoordinate2D])` to render OSRM route geometry.
   - Style with `.stroke(.blue, lineWidth: 4)`.

4. **Current Location Indicator**:
   - `showsUserLocation = true` on the map.
   - Separate `UserLocationManager` (Phase 5) will feed simulated OR real locations.

### Documentation References

- Apple Docs: `Map` SwiftUI initializer (`init(position:interactionModes:showsUserLocation:userTrackingMode:@MapContentBuilder:)`)
- Apple Docs: `MapPolyline`, `Marker`, `Annotation`
- Apple Docs: `MapCameraPosition`, `.userLocation(fallback:)`
- Apple Docs: `MapReader` for coordinate conversion (iOS 17+)

### Verification Checklist

- [ ] Map loads centered on user's current real location.
- [ ] Tapping the map drops a pin at the correct coordinate.
- [ ] Two pins can be placed and are visually distinct (start = green, end = red).
- [ ] `MapPolyline` renders a hardcoded test array of coordinates.
- [ ] `MapUserLocationButton` toggles tracking mode.

### Anti-Pattern Guards

- Do NOT use `MKMapView` directly (UIKit) unless targeting < iOS 17. Prefer SwiftUI `Map`.
- Do NOT add thousands of annotations without reactive filtering; OSRM waypoints are usually < 100.
- Do NOT use `@State` for the route coordinates if they need to be shared across views; use an `@Observable` model class instead.

---

## Phase 3: OpenStreetMap Routing Engine

### What to Implement

1. **OSRM Network Service** (`OSRMRouteService.swift`):
   - `func fetchRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, profile: OSRMProfile) async throws -> OSRMRouteResponse`
   - Build URL: `\{baseURL}/route/v1/\{profile.rawValue}/\{lon1},\{lat1};\{lon2},\{lat2}?geometries=geojson&overview=full&steps=true&annotations=true`
   - `OSRMProfile` enum: `car`, `bike`, `foot`.
   - Decode JSON into a model matching OSRM response shape (`code`, `routes`, `waypoints`).
   - Implement rate-limiting (minimum 1 second between requests) using an `AsyncSemaphore` or `Task.sleep`.

2. **Route Data Models** (`OSRMModels.swift`):
   - `OSRMRouteResponse`: top-level wrapper.
   - `Route`: `geometry`, `legs`, `distance`, `duration`.
   - `Leg`: `steps`, `annotation`, `distance`, `duration`.
   - `Step`: `name`, `distance`, `duration`, `maneuver`.
   - `RouteAnnotation`: `distance`, `duration`, `speed` arrays per node.

3. **GeoJSON Polyline Decoder**:
   - OSRM returns geometry as GeoJSON `LineString`. Decode `coordinates` array of `[longitude, latitude]` pairs.
   - Convert to `[CLLocationCoordinate2D]` for MapKit.

4. **Route Caching**:
   - Cache successful responses in memory (`NSCache`) keyed by start+end+profile hash.
   - Optional: persist to SwiftData for offline replay.

5. **Error Handling**:
   - Map OSRM error codes (`NoSegment`, `TooBig`, `InvalidUrl`) to user-friendly alerts.

### Documentation References

- OSRM GitHub: `docs/http.md` — exact request/response schema for `route` service.
- OSRM Docs: Query parameters (`geometries=geojson`, `overview=full`, `annotations=true`)
- Apple Docs: `URLSession` async/await pattern (`data(from:)`)

### Verification Checklist

- [ ] Unit test: `OSRMRouteService.fetchRoute` returns a valid `Route` for a known city pair (e.g., NYC → LA) using the demo server.
- [ ] Decode geometry produces a `[CLLocationCoordinate2D]` with > 100 points for long routes.
- [ ] `distance` and `duration` values are non-zero and in expected units (meters, seconds).
- [ ] Rate limiter prevents > 1 request per second.
- [ ] Error case: invalid coordinate over ocean returns `NoSegment` and shows an alert.

### Anti-Pattern Guards

- Do NOT use `MKDirections` — it cannot be customized for OSRM data.
- Do NOT ignore the `code` field in the OSRM response; always check `code == "Ok"` before accessing `routes`.
- Do NOT request `alternatives=true` without handling the array properly; default to `alternatives=false` to simplify Phase 3.

---

## Phase 4: Route Model & Speed Profiles

### What to Implement

1. **Route Segment Model** (`RouteSegment.swift`):
   - `struct RouteSegment { let start: CLLocationCoordinate2D; let end: CLLocationCoordinate2D; let distance: CLLocationDistance; let baseDuration: TimeInterval; let annotation: RouteAnnotation? }`
   - Split the OSRM route into segments between each pair of consecutive coordinates in the geometry.

2. **Speed Profile Engine** (`SpeedProfileEngine.swift`):
   - `enum SpeedProfile { case walking; case biking; case driving; case custom(speed: Double) }`
   - Default speeds: walking ~1.4 m/s (5 km/h), biking ~4.2 m/s (15 km/h), driving ~13.9 m/s (50 km/h).
   - `func apply(profile: SpeedProfile, to route: Route) -> TimedRoute`
   - `TimedRoute` contains a `[TimedNode]` where each node has a `coordinate`, `timestamp`, and `speed`.
   - Calculate timestamps by dividing segment distance by profile speed.

3. **Speed Gradients**:
   - `struct SpeedGradient { let fromRatio: Double; let toRatio: Double; let targetSpeed: Double }`
   - Allow users to set a speed for a portion of the route (e.g., 0%–30% of route at walking speed, 30%–100% at driving speed).
   - Interpolate speed linearly between gradient boundaries.
   - Recompute `TimedRoute` when gradients change.

4. **Display Metrics**:
   - Total distance (km/mi)
   - Total duration (hh:mm:ss)
   - Average speed
   - Current segment index while simulating

### Documentation References

- OSRM Docs: `annotations` object structure (`distance`, `duration`, `speed` arrays per leg node)
- Apple Docs: `CLLocationDistance` (meters), `TimeInterval` (seconds)

### Verification Checklist

- [ ] A 10 km route at driving speed (~50 km/h) computes to ~12 minutes.
- [ ] A 10 km route at walking speed (~5 km/h) computes to ~2 hours.
- [ ] Adding a gradient (0–50% walking, 50–100% driving) produces a duration between the two extremes.
- [ ] `TimedRoute` nodes are monotonically increasing in timestamp.

### Anti-Pattern Guards

- Do NOT assume constant speed across the whole route by default; OSRM provides per-segment duration data that accounts for roads/turns.
- Do NOT use `duration` from OSRM as gospel when applying custom speeds; recalculate timestamps based on custom speed × segment distance.
- Do NOT store gradients as absolute distances (prone to floating-point drift); store as normalized ratios (0.0–1.0).

---

## Phase 5: Location Simulation Engine

### What to Implement

1. **Simulation Controller** (`LocationSimulator.swift`):
   - `class LocationSimulator: ObservableObject`
   - `var state: SimulationState { .idle, .running, .paused }`
   - `func startSimulation(route: TimedRoute, playbackSpeed: Double = 1.0)`
   - `func pause()`, `func resume()`, `func stop()`

2. **Internal Location Stream**:
   - Use a `Timer` or `Task.sleep` loop to emit `CLLocation` objects at intervals matching the `TimedRoute`.
   - For each tick:
     - Interpolate between the current node and next node based on elapsed simulation time.
     - Generate a `CLLocation` with `coordinate`, `altitude: 0`, `horizontalAccuracy: 5`, `verticalAccuracy: 5`, `course: bearing`, `speed: currentSpeed`, `timestamp: Date()`.
     - Publish via `@Published var currentSimulatedLocation: CLLocation?`

3. **Bearing/Heading Calculation**:
   - `func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection`
   - Use haversine formula for initial bearing.
   - Set `course` on generated `CLLocation`.

4. **Playback Speed Multiplier**:
   - `playbackSpeed: Double` where `2.0` = 2× realtime.
   - Adjust `Timer` interval or sleep duration by dividing by multiplier.

5. **Coordinate Interpolation**:
   - Linear interpolation between route nodes is acceptable for map display.
   - For higher fidelity, interpolate along the great-circle path (haversine midpoints).

### Documentation References

- Apple Docs: `CLLocation` properties (`coordinate`, `altitude`, `horizontalAccuracy`, `course`, `speed`, `timestamp`)
- Apple Docs: `CLLocationDirection` (degrees, 0 = north)
- Haversine bearing formula (standard geodesy)

### Verification Checklist

- [ ] Unit test: simulating a 1 km straight-line route at walking speed emits ~100 location updates over ~12 minutes (at 1 Hz).
- [ ] Interpolated coordinates lie strictly between start and end nodes.
- [ ] `course` values are stable and point in the direction of travel.
- [ ] Pausing simulation freezes location; resuming continues from the same point.
- [ ] Playback speed `2.0` completes the route in half the time.

### Anti-Pattern Guards

- Do NOT attempt to inject these locations into the system `CLLocationManager` for other apps. This is impossible on non-jailbroken iOS. The simulation is internal to this app only.
- Do NOT set `horizontalAccuracy` to `0` — some consuming apps reject impossibly perfect fixes.
- Do NOT ignore the `timestamp` field on generated `CLLocation`; it should reflect wall-clock time, not simulation time, to look realistic.

---

## Phase 6: Traffic Control Simulation (Stop Signs & Traffic Lights)

### What to Implement

1. **Traffic Control Model** (`TrafficControl.swift`):
   - `struct TrafficControl { let coordinate: CLLocationCoordinate2D; let type: TrafficControlType; let duration: TimeInterval }`
   - `enum TrafficControlType { case stopSign(minimumDuration: TimeInterval); case trafficLight(averageDuration: TimeInterval, variance: TimeInterval) }`

2. **Placement UI**:
   - After a route is generated, allow the user to tap "Add Stop Sign" or "Add Traffic Light" on the map.
   - Snap the tap coordinate to the nearest point on the route polyline.
   - Store traffic controls in an array associated with the route.

3. **Duration Configuration**:
   - Stop signs: default 3 seconds, editable.
   - Traffic lights: default average 45 seconds, variance ±15 seconds. Use `TimeInterval` sliders in a sheet.

4. **Integration with Simulation**:
   - When the simulation reaches a traffic control point:
     - `speed` drops to `0`.
     - Simulation pauses (sleeps) for the control's duration.
     - For traffic lights, randomly sample a duration from `average ± variance` at the start of the simulation.
   - Recompute total route duration including traffic controls.

5. **Visual Indicators**:
   - `MapCircle` or custom `Annotation` around traffic control coordinates.
   - Color: red octagon for stop signs, yellow circle for traffic lights.

### Documentation References

- Apple Docs: `MapCircle` SwiftUI API (iOS 17+)
- Apple Docs: `Annotation` for custom SwiftUI marker content

### Verification Checklist

- [ ] Adding a stop sign increases total route duration by exactly its configured pause time.
- [ ] Traffic light duration varies between runs when `variance > 0`.
- [ ] Simulation speed drops to 0 at control points and resumes afterward.
- [ ] Traffic controls snap to the route line, not arbitrary map positions.

### Anti-Pattern Guards

- Do NOT hardcode traffic control durations as integers in seconds; use `TimeInterval` (Double) for precision.
- Do NOT allow traffic controls outside the route bounds; always snap to the polyline.
- Do NOT pause the whole app/UI thread during a traffic stop; use `Task.sleep` in an actor/isolated context.

---

## Phase 7: Developer Utilities & Life360 Testing Mode

### What to Implement

1. **Life360 Test Mode** (`Life360TestView.swift`):
   - **Purpose**: Provide a transparent, self-contained way for developers to understand how their simulated location data appears to third-party apps.
   - **How it works**: Display the raw properties of the currently simulated `CLLocation`, including:
     - `coordinate` (lat/lon)
     - `horizontalAccuracy`, `verticalAccuracy`
     - `speed`, `course`
     - `timestamp`
     - `sourceInformation?.isSimulatedBySoftware` (iOS 15+)
   - **Spoofing Detection Checklist**:
     - "GPS Jump Test": warn if distance between two simulated points exceeds physically possible travel speed.
     - "Accuracy Sanity": warn if `horizontalAccuracy` is unrealistically low (< 1 m) for extended periods.
     - "Simulation Flag": clearly show `isSimulatedBySoftware == true` and explain that apps like Life360 can read this flag on iOS 15+.
   - **Disclaimer**: Include a prominent disclaimer that this tool is for developer testing only and that third-party apps may reject simulated locations.

2. **GPX Import / Export**:
   - `GPXParser`: Read `.gpx` files ( `<wpt lat="..." lon="...">` and `<trkpt>` ) and convert to `[CLLocationCoordinate2D]`.
   - `GPXExporter`: Write the current simulated route to a `.gpx` file with `<time>` tags, suitable for Xcode location simulation.
   - Use `FileImporter` / `FileExporter` (SwiftUI) for file picking.

3. **Debug Overlay**:
   - Floating panel showing:
     - Current simulation state (idle/running/paused)
     - Current simulated coordinate
     - Next waypoint distance
     - Playback speed multiplier
     - Active traffic controls ahead

### Documentation References

- Apple Docs: `CLLocationSourceInformation` (iOS 15+)
- Apple Docs: `FileImporter`, `FileExporter` (SwiftUI)
- GPX schema: `<gpx version="1.1">`, `<wpt>`, `<trk>`, `<trkseg>`, `<trkpt>`, `<time>`

### Verification Checklist

- [ ] `Life360TestView` shows `isSimulatedBySoftware == true` when a location is internally generated.
- [ ] GPX export produces a file that Xcode accepts in Scheme → Options → Default Location.
- [ ] GPX import parses a standard Strava-exported GPX and renders on the map.
- [ ] Debug overlay updates in real-time during simulation.

### Anti-Pattern Guards

- Do NOT claim the app can "bypass" Life360 detection. iOS 15+ exposes simulation flags; be honest about this limitation.
- Do NOT export GPX with incorrect `<time>` formatting; use ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`).
- Do NOT import arbitrary XML without validation; reject non-GPX files gracefully.

---

## Phase 8: Build & IPA Distribution Pipeline

### What to Implement

1. **Xcode Build Configuration**:
   - Create a `Release` scheme with optimization enabled.
   - Ensure `Info.plist` has correct bundle ID and version.
   - Set `SKIP_INSTALL = NO` for archive compatibility.
   - Set `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` if using Swift packages.

2. **IPA Generation Script** (`scripts/build_ipa.sh`):
   - `xcodebuild archive -scheme <App> -destination 'generic/platform=iOS' -archivePath build/App.xcarchive`
   - `xcodebuild -exportArchive -archivePath build/App.xcarchive -exportPath build/ipa -exportOptionsPlist exportOptions.plist`
   - `exportOptions.plist`:
     ```xml
     <key>method</key>
     <string>development</string>
     <key>teamID</key>
     <string>YOUR_TEAM_ID</string>
     <key>compileBitcode</key>
     <false/>
     ```

3. **Distribution Documentation** (`DISTRIBUTION.md`):
   - **AltStore**: Step-by-step for users (install AltServer, plug in device, refresh weekly).
   - **Sideloadly**: USB-based signing instructions.
   - **Paid Developer Account**: How to register device UDIDs and sign for 1 year.
   - **EU Users (iOS 17.4+)**: Note about third-party marketplaces as a future option.
   - **Limitations**: 7-day expiry for free accounts, 3-app limit, Developer Mode requirement.

4. **OTA Installation Page** (Optional):
   - Simple HTML page with `itms-services://?action=download-manifest&url=...` for enterprise/internal distribution (requires HTTPS).

### Documentation References

- Apple Docs: Xcode `xcodebuild` man pages for `archive` and `-exportArchive`
- AltStore documentation: `faq.altstore.io`
- Sideloadly documentation: `iosgods.com/topic/130167-sideloadly-faq/`

### Verification Checklist

- [ ] `./scripts/build_ipa.sh` produces a valid `.ipa` file.
- [ ] The IPA installs successfully on a test device via AltStore or Sideloadly.
- [ ] App launches and requests location permissions after sideloading.
- [ ] `DISTRIBUTION.md` instructions are tested end-to-end by a second person (or fresh VM).

### Anti-Pattern Guards

- Do NOT commit Apple Team ID or provisioning profile UUIDs to git; use environment variables or `xcconfig` files ignored by git.
- Do NOT use enterprise certificates for public distribution — Apple will revoke them.
- Do NOT distribute via TestFlight without understanding that location spoofing utilities are likely to be rejected.

---

## Final Phase: Integration & End-to-End Verification

### What to Implement

1. **Full User Flow Test**:
   - Drop start pin → Drop end pin → Tap "Generate Route" → See OSRM polyline.
   - Add a traffic light midway → See duration increase.
   - Set speed profile to "Driving" → Start simulation → See blue dot move along route.
   - Open debug overlay → Verify coordinates update every second.
   - Export route to GPX → Import into Xcode → Verify Xcode can play it back.

2. **Performance Checks**:
   - 100 km route with 10,000 geometry points should decode and render in < 500 ms.
   - Simulation at 1 Hz should not drop frames or block the UI.
   - Memory usage should remain < 100 MB during simulation.

3. **Anti-Pattern Grep**:
   - Search for `MKDirections` usage (should be 0).
   - Search for hardcoded `router.project-osrm.org` outside `Config.plist`.
   - Search for `CLLocation` initializers that attempt to forge `sourceInformation`.
   - Search for App Store submission scripts (should be 0).

4. **Device Testing**:
   - Test on physical iPhone with iOS 17+.
   - Verify Developer Mode is enabled.
   - Verify location services work in foreground and background (if applicable).

### Verification Checklist

- [ ] End-to-end flow completes without crashes.
- [ ] Grep checks pass (no forbidden APIs).
- [ ] Performance benchmarks met.
- [ ] App installs via sideloading and runs on a physical device for > 10 minutes.
- [ ] `isSimulatedBySoftware` is correctly reported in the Life360 test view.

---

## Session Boundaries & Execution Order

Each phase above is designed to be self-contained. Recommended execution:

1. **Session 1**: Phase 0 (docs) + Phase 1 (scaffolding) + Phase 2 (map UI).
2. **Session 2**: Phase 3 (OSRM routing) + Phase 4 (speed profiles).
3. **Session 3**: Phase 5 (simulation engine) + Phase 6 (traffic controls).
4. **Session 4**: Phase 7 (developer utilities) + Phase 8 (distribution).
5. **Session 5**: Final integration phase + device testing.

Between sessions, update `Config.plist` and models as needed. Do not proceed to a later phase without completing the verification checklist of the prior phase.
