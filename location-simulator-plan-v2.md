# Location Simulation App v2 — Implementation Plan

**Architecture:** On-device iOS location spoofing via RPPairing + libidevice FFI  
**Target:** iOS 17.4+ (RPPairing required)  
**Distribution:** IPA sideloading (SideStore / AltStore / LiveContainer)  
**Routing Engine:** OpenStreetMap OSRM API  
**VPN:** LocalDevVPN / StosVPN loopback packet tunnel  
**Core Library:** `jkcoxson/idevice` (Rust) compiled to `libidevice_ffi.a`  

---

## Phase 0: Documentation Discovery (Verified)

### Allowed APIs & Handles (from StikDebug source analysis)

| Feature | API / Function | Source File | Confidence |
|---------|---------------|-------------|------------|
| RPPairing tunnel | `tunnel_create_rppairing(..., &adapter, &handshake)` | `idevice.h:5778` | High |
| Location simulation init | `location_simulation_new(remote_server, &handle)` | `idevice.h:~2580` | High |
| Set spoofed location | `location_simulation_set(handle, lat, lon)` | `idevice.h:~2600` | High |
| Clear spoofed location | `location_simulation_clear(handle)` | `idevice.h:~2590` | High |
| Remote server connect | `remote_server_connect_rsd(adapter, handshake, &server)` | `idevice.h` | High |
| VPN loopback | `NEPacketTunnelProvider` with IP rewrite | `StosVPN/PacketTunnelProvider.swift` | High |
| Background location | `CLLocationManager` (3km accuracy, no auto-pause) | `BackgroundLocationManager.swift` | High |
| Silent audio | `AVAudioSession` `.playback` + `.mixWithOthers` | `BackgroundAudioManager.swift` | High |

### Critical Technical Constants (Verified from StikDebug v3.1.0+)

- **Location simulation port:** `49152` (NOT `62078`). A bugfix in PR #355 changed this from `LOCKDOWN_PORT` to `49152` for RPPairing.
- **VPN fake IP:** `10.7.0.1`
- **VPN device IP:** `10.7.0.0`
- **VPN subnet:** `255.255.255.0`
- **Rust FFI library:** `libidevice_ffi.a` (static library)
- **C header:** `idevice.h` (generated via `cbindgen`)
- **Swift module map:** `module.modulemap` (for `import idevice`)

### Anti-Patterns to Avoid

1. **NO `LOCKDOWN_PORT` (62078) for RPPairing:** Use port `49152` for location simulation over RPPairing. The legacy lockdown port is for iOS 16 and below.
2. **NO legacy `libimobiledevice`:** StikDebug uses `jkcoxson/idevice` (pure Rust reimplementation), not the original C `libimobiledevice`.
3. **NO Objective-C++ bridge files:** As of StikDebug v3.1.0, the bridging is pure Swift calling C FFI directly. Old `JITEnableContext.m`, `location_simulation.c`, and `jit.m` were removed.
4. **NO app-level `CLLocation` fabrication:** This architecture uses Apple's developer `com.apple.dt.simulatelocation` service. Do NOT try to manually create `CLLocation` objects and call delegate methods.
5. **NO App Store submission:** Apps using `libidevice` private services will be rejected. Plan for sideloading only.
6. **NO hiding `isSimulatedBySoftware`:** This is impossible. The developer simulation service always sets `isSimulatedBySoftware = true` on iOS 15+. Life360 and similar apps can detect it.

### Verified Constraints

- **iOS 17.4+ minimum:** RPPairing protocol introduced in 17.4. iOS 17.0–17.3 not supported for on-device tunneling.
- **Pairing file required:** A one-time computer step (JitterbugPair / `idevice_pair`) generates `rp_pairing_file.plist`. Must be transferred to the device.
- **VPN required:** A loopback packet-tunnel VPN must be active for `10.7.0.1` routing.
- **Background limits:** iOS will suspend the app. Silent audio + background location updates are required for persistence.
- **Detection:** `CLLocationSourceInformation.isSimulatedBySoftware` will be `true` for all spoofed locations.
- **No Mac after setup:** After pairing file generation and sideloading, operation is fully on-device.

---

## Phase 1: Project Scaffolding & Rust FFI Integration

### What to Implement

1. **Create Xcode Project**:
   - iOS app target, minimum iOS 17.4, SwiftUI interface.
   - Add `libidevice_ffi.a` (static library) to the project.
   - Add `idevice.h` C header to the project.
   - Create `module.modulemap`:
     ```
     module idevice {
         header "idevice.h"
         export *
     }
     ```
   - Set "Import Paths" in Build Settings to the directory containing `module.modulemap`.
   - Add `"$(SRCROOT)/StikJIT/idevice"` to "Header Search Paths".

2. **Swift Package / Dependency Setup**:
   - **Do NOT use Swift Package Manager for libidevice.** The Rust library must be pre-compiled to `libidevice_ffi.a` for the target architecture (arm64 for devices, arm64/x86_64 for simulator).
   - Add a Run Script build phase to verify `libidevice_ffi.a` exists for the current arch.
   - Use Swift Package Manager only for optional utilities (e.g., a GeoJSON parser, if needed).

3. **Info.plist Configuration**:
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>Location access is required for route simulation.</string>
   <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
   <string>Background location is required to keep simulation active.</string>
   <key>NSLocationTemporaryUsageDescriptionDictionary</key>
   <dict>
       <key>SimulationPurpose</key>
       <string>Precise location is needed for accurate route simulation.</string>
   </dict>
   <key>UIBackgroundModes</key>
   <array>
       <string>location</string>
       <string>audio</string>
   </array>
   ```

4. **Folder Structure**:
   ```
   LocationSimulator/
   ├── App/
   │   └── LocationSimulatorApp.swift
   ├── Views/
   ├── ViewModels/
   ├── Models/
   ├── Services/
   │   ├── IDeviceService.swift       (Rust FFI wrapper)
   │   ├── LocationSimService.swift   (location simulation logic)
   │   ├── OSRMService.swift          (routing)
   │   ├── BackgroundLocationManager.swift
   │   └── BackgroundAudioManager.swift
   ├── VPN/
   │   └── PacketTunnelProvider.swift (LocalDevVPN implementation)
   ├── idevice/
   │   ├── idevice.h
   │   ├── module.modulemap
   │   └── libidevice_ffi.a
   ├── Resources/
   │   └── Config.plist
   └── scripts/
       └── build_ipa.sh
   ```

5. **Config.plist**:
   - `OSRMBaseURL`: `https://router.project-osrm.org`
   - `OSRMRateLimit`: `1.0`
   - `LocationSimPort`: `49152`
   - `VpnFakeIP`: `10.7.0.1`
   - `VpnDeviceIP`: `10.7.0.0`
   - `VpnSubnetMask`: `255.255.255.0`

### Documentation References

- StikDebug repo: `StephenDev0/StikDebug` — `StikJIT/idevice/idevice.h`
- StikDebug repo: `StephenDev0/StikDebug` — `StikJIT/Utilities/JITEnableContext.swift`
- jkcoxson/idevice: Rust libidevice reimplementation

### Verification Checklist

- [ ] `import idevice` compiles in Swift without errors.
- [ ] `libidevice_ffi.a` links successfully for arm64 device builds.
- [ ] `Info.plist` contains all required location keys and background modes.
- [ ] `Config.plist` parses at runtime and returns correct values.

### Anti-Pattern Guards

- Do NOT try to compile Rust from source inside Xcode. Pre-build `libidevice_ffi.a` for required architectures.
- Do NOT forget to add `-lidevice_ffi` to "Other Linker Flags" if needed.
- Do NOT use port `62078` for location simulation on iOS 17.4+.

---

## Phase 2: LocalDevVPN — Loopback Packet Tunnel

### What to Implement

1. **Network Extension Target**:
   - Add a "Packet Tunnel Provider" extension target to the Xcode project.
   - Bundle ID: `com.yourcompany.locationsimulator.vpn`
   - Enable `com.apple.developer.networking.networkextension` entitlement with `packet-tunnel-provider`.

2. **PacketTunnelProvider.swift**:
   Implement the loopback VPN that rewrites `10.7.0.1` traffic back to the device:
   ```swift
   import NetworkExtension

   class PacketTunnelProvider: NEPacketTunnelProvider {
       private let tunnelDeviceIp = "10.7.0.0"
       private let tunnelFakeIp = "10.7.0.1"
       private let tunnelSubnetMask = "255.255.255.0"

       override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
           let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelDeviceIp)
           let ipv4 = NEIPv4Settings(addresses: [tunnelDeviceIp], subnetMasks: [tunnelSubnetMask])
           ipv4.includedRoutes = [NEIPv4Route(destinationAddress: tunnelDeviceIp, subnetMask: tunnelSubnetMask)]
           ipv4.excludedRoutes = [.default()]
           settings.ipv4Settings = ipv4
           setTunnelNetworkSettings(settings) { [weak self] error in
               self?.setPackets()
               completionHandler(error)
           }
       }

       private func setPackets() {
           packetFlow.readPackets { [weak self] packets, protocols in
               guard let self = self else { return }
               let deviceip = self.ipv4ToUInt32(self.tunnelDeviceIp)
               let fakeip = self.ipv4ToUInt32(self.tunnelFakeIp)
               var modified = packets
               for i in modified.indices where protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                   modified[i].withUnsafeMutableBytes { bytes in
                       guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                       let src = UInt32(bigEndian: ptr[3])
                       let dst = UInt32(bigEndian: ptr[4])
                       if src == deviceip { ptr[3] = fakeip.bigEndian }
                       if dst == fakeip { ptr[4] = deviceip.bigEndian }
                   }
               }
               self.packetFlow.writePackets(modified, withProtocols: protocols)
               self.setPackets()
           }
       }

       private func ipv4ToUInt32(_ ip: String) -> UInt32 {
           ip.split(separator: ".").reduce(0) { ($0 << 8) + UInt32($1)! }
       }

       override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
           completionHandler()
       }
   }
   ```

3. **VPN Manager (App-side)**:
   - `VPNManager.swift`: Uses `NETunnelProviderManager` to load/save the VPN configuration.
   - Provide UI toggle to start/stop the VPN.
   - Check VPN status before allowing location simulation to start.

### Documentation References

- StikDebug/StosVPN repo (or SideStore/StosVPN): `TunnelProv/PacketTunnelProvider.swift`
- Apple Docs: `NEPacketTunnelProvider`, `NEPacketTunnelNetworkSettings`, `NETunnelProviderManager`

### Verification Checklist

- [ ] VPN starts from the app without crashing.
- [ ] `ifconfig` (or equivalent network check) shows the tunnel interface with `10.7.0.0`.
- [ ] Pinging `10.7.0.1` while VPN is active routes back to the device.
- [ ] Stopping the VPN removes the tunnel interface.

### Anti-Pattern Guards

- Do NOT set `.default()` as an included route. This would route ALL device traffic through the tunnel and break internet connectivity. Use `.default()` in `excludedRoutes` only.
- Do NOT forget the `com.apple.developer.networking.networkextension` entitlement. Without it, the extension target will not compile or run.
- Do NOT run location simulation without the VPN active. The tunnel to `10.7.0.1` will fail.

---

## Phase 3: RPPairing Tunnel & libidevice Service Layer

### What to Implement

1. **Pairing File Import**:
   - `PairingFileManager.swift`: Handle importing `rp_pairing_file.plist` from Files app or AirDrop.
   - Store securely in app documents directory.
   - Validate file format (check for required keys).

2. **IDeviceService.swift** (Rust FFI Wrapper):
   ```swift
   import idevice
   import Foundation

   enum IDeviceError: Error {
       case ffiError(String)
       case tunnelFailed
       case serverConnectFailed
   }

   final class IDeviceService: ObservableObject {
       @Published var isConnected = false
       private var adapter: OpaquePointer?
       private var handshake: OpaquePointer?
       private var remoteServer: OpaquePointer?
       private let port: UInt16 = 49152

       func connect(hostname: String = "10.7.0.1") throws {
           // 1. Load pairing file
           let pairingFile = try loadPairingFile()
           defer { rp_pairing_file_free(pairingFile) }

           // 2. Create RPPairing tunnel
           var addr = sockaddr_in()
           addr.sin_family = sa_family_t(AF_INET)
           addr.sin_port = port.bigEndian
           addr.sin_addr.s_addr = inet_addr(hostname)

           var tunnelAdapter: OpaquePointer?
           var tunnelHandshake: OpaquePointer?

           let ffiError = withUnsafePointer(to: &addr) { addrPtr in
               addrPtr.withMemoryRebound(to: idevice_sockaddr.self, capacity: 1) { boundAddr in
                   tunnel_create_rppairing(
                       boundAddr,
                       socklen_t(MemoryLayout<sockaddr_in>.stride),
                       hostname,
                       pairingFile,
                       nil, nil,
                       &tunnelAdapter,
                       &tunnelHandshake
                   )
               }
           }
           guard ffiError == nil else {
               throw IDeviceError.ffiError(String(cString: idevice_error_to_string(ffiError)))
           }
           self.adapter = tunnelAdapter
           self.handshake = tunnelHandshake

           // 3. Connect remote server
           var server: OpaquePointer?
           let serverErr = remote_server_connect_rsd(tunnelAdapter, tunnelHandshake, &server)
           guard serverErr == nil else {
               throw IDeviceError.serverConnectFailed
           }
           self.remoteServer = server
           self.isConnected = true
       }

       func disconnect() {
           if let server = remoteServer { remote_server_disconnect(server); remoteServer = nil }
           if let hs = handshake { rsd_handshake_free(hs); handshake = nil }
           if let ad = adapter { adapter_free(ad); adapter = nil }
           isConnected = false
       }

       deinit { disconnect() }

       private func loadPairingFile() throws -> OpaquePointer {
           let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
               .appendingPathComponent("rp_pairing_file.plist")
           let data = try Data(contentsOf: url)
           var handle: OpaquePointer?
           let err = data.withUnsafeBytes { bytes in
               rp_pairing_file_from_bytes(bytes.bindMemory(to: UInt8.self).baseAddress!, data.count, &handle)
           }
           guard err == nil else { throw IDeviceError.ffiError("Invalid pairing file") }
           return handle!
       }
   }
   ```

3. **LocationSimService.swift**:
   ```swift
   final class LocationSimService: ObservableObject {
       private var simHandle: OpaquePointer?
       private let deviceService: IDeviceService

       init(deviceService: IDeviceService) {
           self.deviceService = deviceService
       }

       func startSimulation() throws {
           guard let server = deviceService.remoteServer else {
               throw IDeviceError.serverConnectFailed
           }
           var handle: OpaquePointer?
           let err = location_simulation_new(server, &handle)
           guard err == nil else {
               throw IDeviceError.ffiError("Failed to create location simulation handle")
           }
           self.simHandle = handle
       }

       func setLocation(latitude: Double, longitude: Double) throws {
           guard let handle = simHandle else {
               throw IDeviceError.ffiError("Simulation not started")
           }
           let err = location_simulation_set(handle, latitude, longitude)
           guard err == nil else {
               throw IDeviceError.ffiError("Failed to set location")
           }
       }

       func clearLocation() throws {
           guard let handle = simHandle else { return }
           let err = location_simulation_clear(handle)
           guard err == nil else {
               throw IDeviceError.ffiError("Failed to clear location")
           }
       }

       func stopSimulation() {
           if let handle = simHandle {
               location_simulation_free(handle)
               simHandle = nil
           }
       }
   }
   ```

### Documentation References

- StikDebug: `StikJIT/Utilities/JITEnableContext.swift` (tunnel creation pattern)
- StikDebug: `StikJIT/idevice/idevice.h` (exact C signatures)
- jkcoxson/idevice: Rust FFI layer and `cbindgen` header generation

### Verification Checklist

- [ ] `IDeviceService.connect()` successfully creates a tunnel when VPN is active and pairing file is present.
- [ ] `remote_server_connect_rsd()` returns a non-nil `RemoteServerHandle`.
- [ ] `LocationSimService.startSimulation()` creates a non-nil `LocationSimulationHandle`.
- [ ] `setLocation(lat: 37.7749, lon: -122.4194)` changes the device's location in Apple Maps.
- [ ] `clearLocation()` restores real GPS.
- [ ] Disconnecting frees all handles without crashing.

### Anti-Pattern Guards

- Do NOT forget to free `RpPairingFileHandle` after tunnel creation (memory leak).
- Do NOT call `location_simulation_set` with the VPN off — it will silently fail or crash.
- Do NOT store the pairing file in iCloud or insecure locations. Keep it in app documents with reasonable access controls.

---

## Phase 4: Map UI with SwiftUI MapKit

### What to Implement

1. **Main Map View** (`MapView.swift`):
   - SwiftUI `Map(position:)` with `@State var cameraPosition: MapCameraPosition`.
   - Bind to `.userLocation(fallback: .automatic)`.
   - Add `.mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }`.
   - Style: `.mapStyle(.standard(elevation: .realistic, showsTraffic: true))`.

2. **Pin Drop System**:
   - `Marker(coordinate:label:)` for start and end pins (green and red).
   - Tap-to-drop via `MapReader` (iOS 17+):
     ```swift
     MapReader { proxy in
         Map(position: $cameraPosition) { ... }
             .onTapGesture { position in
                 if let coordinate = proxy.convert(position, from: .local) {
                     // drop pin
                 }
             }
     }
     ```
   - Store pins in an `@Observable` route model class.

3. **Route Polyline**:
   - `MapPolyline(_ coordinates: [CLLocationCoordinate2D])` for OSRM route.
   - Style: `.stroke(.blue, lineWidth: 4)`.

4. **Traffic Control Markers**:
   - `MapCircle(center:radius:)` for stop signs (red, 20m radius).
   - `MapCircle(center:radius:)` for traffic lights (yellow, 15m radius).
   - Annotations with custom SwiftUI content for labels.

### Verification Checklist

- [ ] Map centers on user location.
- [ ] Tapping drops a pin at the exact coordinate.
- [ ] Two pins (start/end) are visually distinct.
- [ ] Route polyline renders between pins after OSRM fetch.
- [ ] Traffic controls render as circles snapped to the route.

---

## Phase 5: OpenStreetMap Routing Engine

### What to Implement

1. **OSRMRouteService.swift**:
   - `func fetchRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, profile: OSRMProfile) async throws -> OSRMRouteResponse`
   - URL pattern: `{baseURL}/route/v1/{profile}/{lon1},{lat1};{lon2},{lat2}?geometries=geojson&overview=full&steps=true&annotations=true`
   - Rate limit: 1 request per second (use `Task.sleep` or `AsyncSemaphore`).
   - Decode GeoJSON `LineString` coordinates into `[CLLocationCoordinate2D]`.

2. **Models**:
   - `OSRMProfile`: `.car`, `.bike`, `.foot`
   - `OSRMRouteResponse`, `Route`, `Leg`, `Step`, `RouteAnnotation`

3. **Caching**:
   - In-memory `NSCache` keyed by `start+end+profile` hash.

### Verification Checklist

- [ ] Fetching NYC -> LA returns a valid route with `distance` > 0 and `duration` > 0.
- [ ] Geometry decode produces > 100 coordinates.
- [ ] Rate limiter prevents > 1 req/sec.

---

## Phase 6: Route Model, Speed Profiles & Gradients

### What to Implement

1. **TimedRoute Model**:
   - Split OSRM geometry into segments.
   - `TimedNode`: `coordinate`, `timestamp`, `speed`, `course`

2. **Speed Profiles**:
   - `enum SpeedProfile { case walking(1.4); case biking(4.2); case driving(13.9); case custom(Double) }` (m/s)

3. **Speed Gradients**:
   - `struct SpeedGradient { let fromRatio: Double; let toRatio: Double; let targetSpeed: Double }`
   - Interpolate speed linearly between gradient boundaries.
   - Recompute `TimedRoute` on gradient changes.

4. **Metrics**:
   - Total distance, total duration, average speed.

### Verification Checklist

- [ ] 10 km driving route ~= 12 minutes.
- [ ] 10 km walking route ~= 2 hours.
- [ ] Mixed gradient produces intermediate duration.
- [ ] `TimedNode` timestamps are monotonically increasing.

---

## Phase 7: Route Playback Engine

### What to Implement

1. **RoutePlayer.swift**:
   - `class RoutePlayer: ObservableObject`
   - `state: .idle, .running, .paused, .completed`
   - `func start(route: TimedRoute, playbackMultiplier: Double = 1.0)`
   - `func pause()`, `func resume()`, `func stop()`

2. **Coordinate Stream**:
   - `Timer` or `Task.sleep` loop at 1 Hz (or faster for smooth playback).
   - Interpolate current position along `TimedRoute` based on elapsed time.
   - Call `locationSimService.setLocation(lat: currentLat, lon: currentLon)` at each tick.

3. **Traffic Control Handling**:
   - When approaching a stop sign or traffic light:
     - Set location at the control coordinate.
     - Pause the player for the control's duration.
     - Resume after duration elapses.
   - For traffic lights: sample random duration from `average +/- variance` at simulation start.

4. **Bearing Calculation**:
   - Haversine initial bearing between current and next node.
   - Not sent to the system (location_simulation only takes lat/lon), but stored for UI display.

5. **Progress Tracking**:
   - `@Published var currentCoordinate: CLLocationCoordinate2D?`
   - `@Published var progressRatio: Double` (0.0 to 1.0)
   - `@Published var nextTrafficControl: TrafficControl?`

### Verification Checklist

- [ ] 1 km route at walking speed emits ~100 setLocation calls over ~12 minutes (1 Hz, 1x speed).
- [ ] Playback at 2x speed completes in ~6 minutes.
- [ ] Pausing stops location updates; resuming continues from the same point.
- [ ] Stop sign adds exactly its configured duration to total time.
- [ ] Interpolated coordinates lie strictly between route nodes.
- [ ] Apple Maps shows the blue dot moving smoothly along the route.

### Anti-Pattern Guards

- Do NOT call `setLocation` more than ~10 Hz. The system developer service does not need ultra-high-frequency updates, and rapid calls may cause instability.
- Do NOT skip traffic control durations. Always pause at control points.
- Do NOT interpolate across traffic controls. The device should "stop" at the control coordinate.

---

## Phase 8: Background Persistence

### What to Implement

1. **BackgroundLocationManager.swift**:
   ```swift
   final class BackgroundLocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
       private let manager = CLLocationManager()
       private var activityCount = 0

       override init() {
           super.init()
           manager.delegate = self
           manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
           manager.distanceFilter = CLLocationDistanceMax
           manager.allowsBackgroundLocationUpdates = true
           manager.pausesLocationUpdatesAutomatically = false
       }

       func startKeepAlive() {
           activityCount += 1
           if activityCount == 1 {
               manager.startUpdatingLocation()
           }
       }

       func stopKeepAlive() {
           activityCount -= 1
           if activityCount <= 0 {
               activityCount = 0
               manager.stopUpdatingLocation()
           }
       }

       func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
           // No-op; we only need the keep-alive side effect
       }
   }
   ```

2. **BackgroundAudioManager.swift**:
   ```swift
   final class BackgroundAudioManager: ObservableObject {
       private var engine: AVAudioEngine?
       private var player: AVAudioPlayerNode?
       private var healthCheckTimer: Timer?

       func startSilence() throws {
           let session = AVAudioSession.sharedInstance()
           try session.setCategory(.playback, options: .mixWithOthers)
           try session.setActive(true)

           let engine = AVAudioEngine()
           let player = AVAudioPlayerNode()
           engine.attach(player)

           let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
           engine.connect(player, to: engine.mainMixerNode, format: format)
           try engine.start()

           let frameCount: AVAudioFrameCount = 44100
           guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
           buffer.frameLength = frameCount
           // Buffer is zero-initialized (silence)

           player.scheduleBuffer(buffer, at: nil, options: .loops)
           player.play()

           self.engine = engine
           self.player = player

           healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
               guard let self = self, let player = self.player else { return }
               if !player.isPlaying {
                   player.scheduleBuffer(buffer, at: nil, options: .loops)
                   player.play()
               }
           }
       }

       func stopSilence() {
           healthCheckTimer?.invalidate()
           player?.stop()
           engine?.stop()
           player = nil
           engine = nil
       }
   }
   ```

3. **Background Orchestrator** (`BackgroundManager.swift`):
   - When simulation starts: call `backgroundLocationManager.startKeepAlive()` + `backgroundAudioManager.startSilence()`.
   - When simulation stops: call both stop methods.
   - Use reference counting if multiple features need keep-alive.

### Verification Checklist

- [ ] App continues updating location for > 5 minutes while backgrounded.
- [ ] Audio session does not interfere with music/podcast apps (`.mixWithOthers`).
- [ ] Health check timer recovers audio if another app interrupts it.
- [ ] Location manager uses `kCLLocationAccuracyThreeKilometers` to minimize battery drain.
- [ ] No excessive battery usage reported in Settings -> Battery.

### Anti-Pattern Guards

- Do NOT use `kCLLocationAccuracyBest` for background keep-alive. This drains battery rapidly.
- Do NOT set `.duckOthers` on the audio session. This would lower other apps' volume.
- Do NOT forget to call `stopKeepAlive` / `stopSilence` when simulation ends. Leaked background tasks will drain battery.

---

## Phase 9: Developer Utilities & Detection Transparency

### What to Implement

1. **Simulation Transparency View** (`TransparencyView.swift`):
   - Display current spoofed coordinate.
   - Show a large red banner: `isSimulatedBySoftware == true`.
   - Explain that apps checking `CLLocationSourceInformation` will detect this.
   - List detection vectors:
     - `isSimulatedBySoftware` flag (iOS 15+)
     - Impossible GPS jumps
     - Wi-Fi BSSID / cell tower mismatch
     - Accelerometer inconsistency
   - **Disclaimer**: "This tool uses Apple's developer location simulation service. Third-party apps can detect simulated locations."

2. **GPX Import / Export**:
   - `GPXParser`: Read `.gpx` `<wpt>` and `<trkpt>` elements.
   - `GPXExporter`: Write route to `.gpx` with `<time>` tags (ISO 8601).
   - Use SwiftUI `FileImporter` / `FileExporter`.

3. **Debug Overlay**:
   - Current simulation state
   - Current coordinate (spoofed)
   - Real coordinate (from `CLLocationManager`, if available)
   - Next waypoint distance
   - Next traffic control distance and type
   - Playback speed multiplier
   - VPN status
   - Tunnel connection status

### Verification Checklist

- [ ] `TransparencyView` shows `isSimulatedBySoftware == true` when simulation is active.
- [ ] GPX export produces valid XML that Xcode accepts.
- [ ] GPX import parses a Strava-exported file correctly.
- [ ] Debug overlay updates in real-time during simulation.

### Anti-Pattern Guards

- Do NOT claim the app "bypasses" detection. Be transparent.
- Do NOT export GPX with malformed timestamps. Use `ISO8601DateFormatter`.
- Do NOT import non-GPX XML without validation.

---

## Phase 10: Build & IPA Distribution Pipeline

### What to Implement

1. **Xcode Build Configuration**:
   - Release scheme with optimizations.
   - `SKIP_INSTALL = NO`.
   - Ensure Network Extension target is embedded in the app target.
   - Add `libidevice_ffi.a` for both `arm64` (device) and `arm64/x86_64` (simulator).

2. **IPA Generation Script** (`scripts/build_ipa.sh`):
   ```bash
   #!/bin/bash
   set -e
   SCHEME="LocationSimulator"
   xcodebuild archive \
       -scheme "$SCHEME" \
       -destination 'generic/platform=iOS' \
       -archivePath "build/$SCHEME.xcarchive"
   xcodebuild -exportArchive \
       -archivePath "build/$SCHEME.xcarchive" \
       -exportPath "build/ipa" \
       -exportOptionsPlist "scripts/exportOptions.plist"
   echo "IPA built at: build/ipa/$SCHEME.ipa"
   ```

3. **exportOptions.plist**:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>method</key>
       <string>development</string>
       <key>teamID</key>
       <string>YOUR_TEAM_ID</string>
       <key>compileBitcode</key>
       <false/>
       <key>provisioningProfiles</key>
       <dict>
           <key>com.yourcompany.locationsimulator</key>
           <string>YOUR_APP_PROFILE</string>
           <key>com.yourcompany.locationsimulator.vpn</key>
           <string>YOUR_VPN_PROFILE</string>
       </dict>
   </dict>
   </plist>
   ```

4. **Distribution Documentation** (`DISTRIBUTION.md`):
   - SideStore / AltStore installation steps.
   - Pairing file generation (one-time computer step using JitterbugPair).
   - LocalDevVPN installation and activation.
   - 7-day refresh reminder for free Apple IDs.
   - Paid Developer Account option (1-year expiry).
   - EU third-party marketplace note (iOS 17.4+).

### Verification Checklist

- [ ] Script produces a valid `.ipa` containing both app and VPN extension.
- [ ] IPA installs via SideStore without errors.
- [ ] VPN extension appears in Settings -> VPN after first launch.
- [ ] App requests location permissions and runs for > 10 minutes on a physical device.

### Anti-Pattern Guards

- Do NOT commit Team ID or provisioning profile UUIDs to git. Use environment variables or `xcconfig`.
- Do NOT use enterprise certificates for public distribution.
- Do NOT attempt TestFlight submission.

---

## Final Phase: Integration & End-to-End Verification

### Full User Flow Test

1. Install app via SideStore + import pairing file.
2. Enable LocalDevVPN.
3. Drop start pin -> Drop end pin -> Generate Route (OSRM).
4. Add a traffic light midway.
5. Set speed profile to "Driving" -> Start Simulation.
6. Open Apple Maps -> Verify blue dot moves along the route.
7. Open Transparency View -> Verify `isSimulatedBySoftware == true`.
8. Background the app -> Verify simulation continues for > 5 minutes.
9. Stop simulation -> Verify real location returns in Apple Maps.
10. Export route to GPX -> Import to Xcode -> Verify Xcode plays it back.

### Performance Checks

- 100 km route decodes and renders in < 500 ms.
- 1 Hz location updates do not block the UI.
- Memory usage < 150 MB during simulation.
- Battery drain < 5% per hour (background location + silent audio).

### Anti-Pattern Grep

- Search for `62078` (should only appear in historical comments, if at all).
- Search for `locationd` or `lockdown_location_simulation` (RPPairing uses `location_simulation_*`).
- Search for hardcoded `router.project-osrm.org` outside `Config.plist`.
- Search for `MKDirections` (should be 0).

---

## Session Boundaries & Execution Order

1. **Session 1**: Phase 1 (scaffolding + FFI) + Phase 2 (VPN extension).
2. **Session 2**: Phase 3 (RPPairing tunnel + location sim service) + Phase 4 (map UI).
3. **Session 3**: Phase 5 (OSRM routing) + Phase 6 (speed profiles).
4. **Session 4**: Phase 7 (route playback) + Phase 8 (background persistence).
5. **Session 5**: Phase 9 (developer utilities) + Phase 10 (distribution).
6. **Session 6**: Final integration + device testing.

Do not proceed to the next phase until the previous phase's verification checklist is complete.
