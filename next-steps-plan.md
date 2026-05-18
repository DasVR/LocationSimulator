# LocationSimulator — Next Steps Plan

**Status:** Core architecture implemented, UI wired, services complete.  
**Goal:** Move from source tree to buildable, testable, distributable app.

---

## Phase A: Xcode Project Creation

### Objective
Create a functioning `.xcodeproj` from the current source tree so the app compiles on macOS.

### Checklist
1. Create project with **iOS App** template (SwiftUI, Swift, iOS 17.4 target)
2. Add all existing `.swift` files to correct groups:
   - `App/` → app entry point
   - `Views/` → SwiftUI views
   - `ViewModels/` → Observable view models
   - `Models/` → data models
   - `Services/` → business logic + networking
   - `VPN/` → `PacketTunnelProvider.swift`
   - `idevice/` → C header + module map
3. Configure build settings:
   - **Library Search Paths:** add `$(PROJECT_DIR)/LocationSimulator/idevice`
   - **Other Linker Flags:** add `-lidevice` or explicit path to `libidevice_ffi.a`
   - **Swift Compiler - Search Paths:** add `$(PROJECT_DIR)/LocationSimulator/idevice` to Import Paths for `module.modulemap`
   - **Frameworks:** add `NetworkExtension`, `AVFoundation`, `CoreLocation`, `MapKit`
4. Add resource files:
   - `Info.plist` (set as custom, not generated)
   - `Resources/Config.plist`
   - `LocationSimulator.entitlements`
5. Add `libidevice_ffi.a` to the project (even as placeholder; build will fail until replaced)
6. Verify **Signing & Capabilities:**
   - App Groups (if needed for VPN)
   - Personal VPN capability
   - Background Modes: Location, Audio

### Verification
- [ ] `xcodebuild -project LocationSimulator.xcodeproj -scheme LocationSimulator -destination 'platform=iOS Simulator,name=iPhone 15' build` completes without errors (excluding missing library)
- [ ] No red files in navigator
- [ ] Build settings reference relative paths, not absolute

### Anti-Patterns
- Do NOT commit `.xcodeproj` user data (`xcuserdata/`)
- Do NOT use absolute paths in build settings
- Do NOT add the VPN extension as a separate target yet unless needed

---

## Phase B: Unit Tests

### Objective
Add `LocationSimulatorTests` target with behavioral coverage for critical paths.

### Checklist
1. **OSRMRouteService Tests**
   - Decode `[lon, lat]` → `CLLocationCoordinate2D(latitude:longitude:)` correctly
   - Cache hit returns without network call
   - Rate limiting sleeps between requests
   - `invalidResponse` thrown on malformed JSON
   - `noRoute` thrown when OSRM code != "Ok"

2. **SpeedProfileEngine Tests**
   - Gradient 0.0 produces max speed
   - Gradient 1.0 produces min speed
   - Bearing calculation between two coordinates matches haversine expectation
   - `computeTimedRoute` returns segments with non-negative durations

3. **GPX Tests**
   - `GPXParser` handles valid GPX 1.1 with `<trkpt>` elements
   - `GPXParser` throws on malformed XML
   - `GPXExporter` output round-trips through parser (coordinates preserved)
   - `GPXExporter` generates ISO 8601 timestamps

4. **RoutePlayer Tests**
   - `start()` rejects double-start
   - Playback multiplier clamped to `[0.1, 10.0]`
   - Traffic controls trigger pause at correct coordinate
   - `processedControlIDs` prevents duplicate triggers
   - Timer invalidates on `stop()`

5. **TrafficControl Tests**
   - `==` ignores UUID (compares coordinate/type/duration)
   - `trafficLight()` random duration within `average ± variance`
   - `stopSign()` uses `minimumDuration`

6. **VPN / PacketTunnel Tests**
   - `recomputeIPv4Checksum` yields 0xFFFF for valid header
   - IP rewrite swaps `10.7.0.1` ↔ `10.7.0.0`

### Verification
- [ ] `Cmd+U` runs all tests and passes
- [ ] Code coverage ≥ 60% for tested modules

### Anti-Patterns
- Do NOT mock `URLSession` for OSRM tests — use a local stub or capture request
- Do NOT test SwiftUI views directly; test view model outputs

---

## Phase C: Compilation Fixes & Polish

### Objective
Fix any build errors that surface once the project is in Xcode, and polish rough edges.

### Known Risk Areas
1. **FFI bridging:** `import idevice` may fail if module map path is wrong
2. **Actor isolation:** `@MainActor` on `MapViewModel` vs `actor OSRMRouteService` — ensure calls across isolation boundaries use `await`
3. **NetworkExtension entitlement:** `NEPacketTunnelProvider` requires `com.apple.developing.networking.vpn.api` entitlement (paid dev account)
4. **MapKit API availability:** `MapPolyline`, `MapCircle`, `MapReader` require iOS 17.0+ — confirm deployment target
5. **SwiftData / Observation:** `@Observable` on classes requires `import Observation` and iOS 17.0+

### Checklist
1. Fix any `Cannot find 'idevice' in scope` by verifying module map import paths
2. Fix any `Call to main actor-isolated instance method` by adding `await` or `@MainActor`
3. Fix any `NEVPNError` by adding correct entitlements
4. Resolve all warnings (force unwraps, unused variables, deprecated APIs)
5. Run **Product → Analyze** and fix static analyzer issues
6. Verify no retain cycles in `RoutePlayer` timer / `IDeviceService` closures

### Verification
- [ ] Zero build errors, zero warnings at `-Wall -Wextra` equivalent
- [ ] Static analyzer clean
- [ ] App launches in Simulator without crashing

---

## Phase D: Device Testing Prep

### Objective
Prepare for on-device testing with real hardware (iPhone, iOS 17.4+).

### Prerequisites
- Paid Apple Developer account (for NetworkExtension VPN entitlement)
- iPhone running iOS 17.4 or later
- Pairing file (`rp_pairing_file.plist`) generated via JitterbugPair or `idevice_pair`
- `libidevice_ffi.a` compiled for iOS arm64 / x86_64 simulator

### Checklist
1. **Build `libidevice_ffi.a`**
   - Clone `jkcoxson/idevice`
   - Compile with `cargo build --release --target aarch64-apple-ios`
   - Also build for `aarch64-apple-ios-sim` and `x86_64-apple-ios` if simulator testing needed
   - Use `lipo` to create universal binary if desired
   - Place `.a` and `idevice.h` in `LocationSimulator/idevice/`

2. **Signing Setup**
   - Configure Xcode with your Apple ID / Team
   - Set bundle ID to something unique (e.g., `com.yourname.locosim`)
   - Add `NetworkExtension` entitlements to both app and extension targets
   - Trust developer certificate on device (Settings → VPN & Device Management)

3. **Install Pairing File**
   - Transfer `rp_pairing_file.plist` to device (AirDrop, Files app)
   - Use in-app `PairingFileManager` to import and validate

4. **VPN Configuration**
   - First launch will prompt to allow VPN
   - Verify `PacketTunnelProvider` starts without crash
   - Check `ifconfig` / `ipconfig` shows `10.7.0.1` assigned

### Verification
- [ ] App installs on device via Xcode → Run
- [ ] Pairing file imports without error
- [ ] VPN toggle in app connects successfully
- [ ] Location simulation sets coordinates (check with Apple Maps)

---

## Phase E: Build & Distribution

### Objective
Produce a signed `.ipa` suitable for sideloading.

### Checklist
1. **Archive**
   - Select **Any iOS Device (arm64)** or connected device as destination
   - Product → Archive
   - In Organizer, verify build size (< 50 MB ideal)

2. **Export**
   - Use **Ad Hoc** or **Development** distribution method
   - Include bitcode = NO (deprecated)
   - Strip Swift symbols = YES (reduce size)

3. **IPA Validation**
   - Unzip `.ipa` and inspect `Payload/LocationSimulator.app/`
   - Verify `libidevice_ffi.a` is statically linked (not present as loose file)
   - Verify `Info.plist` has correct background modes
   - Verify `embedded.mobileprovision` contains VPN entitlement

4. **Distribution Channels**
   - **SideStore:** User installs SideStore, loads IPA
   - **AltStore:** Same flow with AltServer / AltStore
   - **LiveContainer:** For users who prefer not to re-sign frequently
   - **Direct (paid dev):** Xcode + device provisioning

5. **Documentation**
   - Update `DISTRIBUTION.md` with actual installation steps
   - Add screenshots of Settings → VPN & Device Management → Trust
   - Include troubleshooting section for common sideload failures

### Verification
- [ ] `build_ipa.sh` runs end-to-end without error
- [ ] Exported `.ipa` installs successfully via SideStore / AltStore
- [ ] App launches, all tabs functional
- [ ] Location spoofing works on-device

---

## Appendix: File Inventory

| Path | Purpose |
|------|---------|
| `App/LocationSimulatorApp.swift` | `@main` entry point |
| `Views/ContentView.swift` | Root `TabView` with 5 tabs |
| `Views/MapView.swift` | MapKit + tap-to-drop + route overlay |
| `Views/PairingFileImportView.swift` | Pairing file picker / importer |
| `Views/TransparencyView.swift` | Detection disclosure UI |
| `Views/DebugOverlayView.swift` | Tunnel / VPN status display |
| `ViewModels/MapViewModel.swift` | Pins, route, traffic controls |
| `Models/TrafficControl.swift` | Stop signs, traffic lights |
| `Models/MapPin.swift` | Start / end / traffic pins |
| `Models/SpeedProfile.swift` | Walking, cycling, driving profiles |
| `Models/TimedRoute.swift` | Route + timestamp segments |
| `Services/IDeviceService.swift` | RPPairing tunnel wrapper |
| `Services/LocationSimService.swift` | `com.apple.dt.simulatelocation` client |
| `Services/OSRMRouteService.swift` | OpenStreetMap routing actor |
| `Services/RoutePlayer.swift` | 1 Hz playback with traffic pauses |
| `Services/SpeedProfileEngine.swift` | Gradient-based speed computation |
| `Services/BackgroundAudioManager.swift` | Silent audio for background |
| `Services/BackgroundLocationManager.swift` | 3km accuracy background location |
| `Services/BackgroundOrchestrator.swift` | Coordinates audio + location |
| `Services/VPNManager.swift` | `NETunnelProviderManager` lifecycle |
| `Services/PairingFileManager.swift` | Pairing file I/O + validation |
| `VPN/PacketTunnelProvider.swift` | Loopback IP rewrite |
| `Resources/Config.plist` | OSRM base URL, rate limits, VPN IPs |
| `Info.plist` | Location permissions, background modes |
| `LocationSimulator.entitlements` | VPN, background modes |
| `idevice/idevice.h` | C FFI header |
| `idevice/module.modulemap` | Swift import mapping |
| `scripts/build_ipa.sh` | Archive + export automation |
| `README.md` | Project overview |
| `DISTRIBUTION.md` | Sideloading guide |

---

**Decision Required:** Phase A requires macOS + Xcode. If you are on Linux, this phase must be deferred until you switch to a Mac or use a remote build service (GitHub Actions with macOS runner, or Xcode Cloud). Phases B and C can be partially done on Linux using `swift test` if a `Package.swift` is added, but UI tests and device builds need macOS.
