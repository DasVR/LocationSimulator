# LocationSimulator — Comprehensive Issues Audit

> Audit date: 2026-05-18
> Fix session: 2026-05-18
> Plans reviewed: `location-simulator-plan.md` (v1, superseded), `location-simulator-plan-v2.md` (canonical)
> Scope: All source under `LocationSimulator/` and `LocationSimulatorTests/`, plus `project.yml` and CI configuration.

---

## Fixes Applied This Session

| Issue | Status | What Changed |
|-------|--------|--------------|
| C1 | **FIXED** | `project.yml` deployment target changed `"26.5"` → `"17.4"` |
| C2 | **FIXED** | Added `LocationSimulatorVPN` extension target to `project.yml` with `type: app-extension`, `embed: true`, `packet-tunnel-provider` entitlement |
| C3 | **FIXED** | CI Xcode version `'26.3'` → `'26.5'`, runner `macos-latest` → `macos-26` |
| C4 | **FIXED** | Downloaded `idevice-xcframework-v0.1.62.zip`, extracted `IDevice.xcframework` into `LocationSimulator/idevice/` |
| C5 | **FIXED** | Replaced hand-written `idevice.h` with official xcframework header; updated Swift imports `idevice` → `IDevice`; aligned FFI error handling (`IdeviceFfiError`) |
| H1 | **FIXED** | Replaced unbounded `Dictionary` cache with `NSCache<NSString, OSRMRouteResponseWrapper>` in `OSRMRouteService` |
| H2 | **FIXED** | Rewrote `GPXParser` from regex to `XMLParser` with `GPXParserDelegate` |
| H3 | **FIXED** | Added `didSet` clamp to `RoutePlayer.playbackMultiplier` (0.1…10.0) |
| H4 | **FIXED** | Removed `@MainActor` from `BackgroundAudioManager`; moved engine setup to dedicated `DispatchQueue` |
| H5 | **FIXED** | Added `reconnect(hostname:maxAttempts:)` with exponential backoff and `@Published var lastError` to `IDeviceService` |
| H6 | **FALSE CLAIM** | `RoutePlayer` already calls `locationSimService.setLocation()` on every tick — no change needed |
| M1 | **FIXED** | Replaced `NavigationView` with `NavigationStack` in `PairingFileImportView` |
| M2 | **FIXED** | Added `@Environment(\.scenePhase)` to `ContentView`; reconnects tunnel and restarts `BackgroundOrchestrator` on `.active` |
| M3 | **FIXED** | Implemented `SettingsTabView` with OSRM base URL, speed unit picker, and cache clear button |
| M5 | **FIXED** | Added custom speed `TextField` (m/s) when `.custom` profile selected in `SimulateTabView` |
| M6 | **FIXED** | Added optional `baseURL` parameter to `OSRMRouteService.init(baseURL:)` |
| M7 | **ALREADY OK** | `TrafficControl.trafficLight()` samples variance at creation time |

## Remaining Open Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| M4 | Medium | Speed gradient UI — no per-segment speed controls yet |
| L1 | Low | Expand unit test coverage beyond OSRM tests |
| L2 | Low | Accessibility labels on map overlay buttons |
| L3 | Low | Map pin overlap handling |
| L4 | Low | Dark mode map styling |
| Phase 6 | — | `isSimulatedBySoftware` transparency sheet exists (`TransparencyView.swift`) but may need copy review |
| Phase 6 | — | CI IPA export step not yet added |

---

---

## How to Read This Document

Each issue is tagged with a **Severity** and a **Plan Phase**.

| Severity | Meaning |
|----------|---------|
| **Critical** | Blocks compilation, linking, or basic project generation. The app cannot be built or run until fixed. |
| **High** | Causes runtime crashes, memory exhaustion, or core feature failure under normal use. |
| **Medium** | Incomplete feature or degraded UX. App functions but lacks advertised capability. |
| **Low** | Polish, accessibility, or performance niceties. Nice-to-have. |

| Plan Phase | Source Document |
|------------|-----------------|
| Phase 0 | v2 — Documentation Discovery |
| Phase 1 | v2 — Xcode Project & FFI Bridge |
| Phase 2 | v2 — VPN Tunnel & Packet Tunnel Extension |
| Phase 3 | v2 — Route Engine & OSRM Integration |
| Phase 4 | v2 — Location Simulation Service |
| Phase 5 | v2 — Route Playback & Speed Profiles |
| Phase 6 | v2 — Background Persistence |
| Phase 7 | v2 — UI/UX & Transparency |
| Phase 8 | v2 — Testing & Verification |
| Phase 9 | v2 — Build & Distribution |
| N/A | Not tied to a specific plan phase |

---

## Critical Issues (Build Blockers)

### #C1 — Invalid iOS Deployment Target in `project.yml`
- **Severity:** Critical
- **Phase:** Phase 1, Phase 9
- **Location:** `project.yml:10`
- **Problem:** `deploymentTarget: "26.5"` is invalid. iOS major versions currently cap at 18.x. The app requires iOS 17.4+ for RPPairing support, but `26.5` will cause `xcodebuild` to fail with an unsupported platform version error.
- **Fix:** Change to `deploymentTarget: "17.4"`.
- **Status:** Not fixed.

### #C2 — Missing VPN Extension Target in `project.yml`
- **Severity:** Critical
- **Phase:** Phase 2
- **Location:** `project.yml`
- **Problem:** The `VPN/` directory contains `PacketTunnelProvider.swift`, but `project.yml` defines **zero** `app-extension` targets. XcodeGen will not include the NEPacketTunnelProvider in the generated `.xcodeproj`, so the loopback tunnel cannot be built, signed, or embedded. The entire RPPairing tunnel architecture depends on this extension.
- **Fix:** Add a second target of type `app-extension` with `platform: iOS` and `deploymentTarget: "17.4"`, referencing `VPN/PacketTunnelProvider.swift`. Reference it as a dependency of the main `LocationSimulator` target.
- **Status:** Not implemented.

### #C3 — CI References Nonexistent Xcode Version
- **Severity:** Critical
- **Phase:** Phase 9
- **Location:** `.github/workflows/ios.yml:22`
- **Problem:** `xcode-version: '26.3'` does not exist. GitHub Actions will fail at the `setup-xcode` step. Current stable Xcode versions are 15.x and 16.x.
- **Fix:** Change to a real version string such as `'15.4'` or `'16.0'`, matching the Swift 5.9 toolchain declared in `project.yml`.
- **Status:** Not fixed.

### #C4 — `libidevice_ffi.a` Static Library Is Completely Missing
- **Severity:** Critical
- **Phase:** Phase 1
- **Location:** `LocationSimulator/idevice/`
- **Problem:** The directory only contains `.gitkeep`, `idevice.h`, and `module.modulemap`. The linker flag `-lidevice` in `project.yml` and the `LIBRARY_SEARCH_PATHS` reference a binary that does not exist. Any attempt to build will fail at link time with `library not found for -lidevice`.
- **Fix:** Either (a) cross-compile `jkcoxson/idevice` from Rust to iOS `arm64`/`x86_64`, produce `libidevice_ffi.a`, and commit it, or (b) add a Rust toolchain build step in CI that compiles the library before `xcodebuild` runs.
- **Status:** Not implemented.
- **Open Question:** Does the Rust crate expose the exact symbols assumed in `idevice.h`? Until the binary is built and linked, this is unverified.

### #C5 — Hand-Written `idevice.h` May Not Match Rust FFI Signatures
- **Severity:** Critical
- **Phase:** Phase 1
- **Location:** `LocationSimulator/idevice/idevice.h`
- **Problem:** The header was written manually based on research into `jkcoxson/idevice`. If the actual Rust FFI exports different symbol names, argument orders, or calling conventions, the app will either fail to link or crash at runtime when calling `location_simulation_set`.
- **Fix:** Build `libidevice_ffi.a`, then run `nm libidevice_ffi.a | grep -E "location_simulation|tunnel_create|rsd_|remote_server|adapter|pairing_file"` to verify exported symbols match the header. Adjust `idevice.h` and `module.modulemap` accordingly.
- **Status:** Unverified.

---

## High Issues (Runtime Risks / Major Feature Gaps)

### #H1 — Unbounded OSRM Response Cache
- **Severity:** High
- **Phase:** Phase 3
- **Location:** `LocationSimulator/Services/OSRMRouteService.swift`
- **Problem:** `private var cache: [String: OSRMRouteResponse] = [:]` grows forever. Generating many routes across a long session will exhaust memory. No eviction policy exists.
- **Fix:** Replace with `NSCache<NSString, OSRMRouteResponseWrapper>` (NSCache auto-evicts under memory pressure) or use an LRU wrapper with a max entry count (e.g., 50).
- **Status:** Not fixed.

### #H2 — Regex-Based GPX Parsing Is Brittle
- **Severity:** High
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Services/GPXParser.swift` (inferred from `ContentView` references)
- **Problem:** If a GPX file contains namespaces, CDATA, whitespace variations, or XML comments, regex extraction of `<trkpt lat="..." lon="...">` will fail silently or return malformed coordinates.
- **Fix:** Rewrite using `XMLParser` (Foundation) or `Codable` with a proper GPX XML decoder. This is a well-trodden path and far more reliable.
- **Status:** Not fixed.

### #H3 — `RoutePlayer` Has No Defensive Bounds on `playbackMultiplier`
- **Severity:** High
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Services/RoutePlayer.swift`
- **Problem:** While `start(route:...)` clamps the multiplier to `0.1...10.0`, there is no guarantee external callers (e.g., UI bindings via `@Published`) won't write directly to a stored property if one is added later. More importantly, if the timer tick interval becomes sub-millisecond due to a math error, the runloop will spin.
- **Fix:** Make `playbackMultiplier` a computed property with a didSet clamp, or centralise all updates through `start()`.
- **Status:** Partial — clamp exists in `start()` but not defensively elsewhere.

### #H4 — `BackgroundAudioManager` Pinned to `@MainActor`
- **Severity:** High
- **Phase:** Phase 6
- **Location:** `LocationSimulator/Services/BackgroundAudioManager.swift`
- **Problem:** `AVAudioEngine.start()` and buffer scheduling are audio I/O operations. Running them on the main actor can cause frame drops in the UI if the engine stutters or takes time to initialise. More critically, if the main thread is blocked, the audio engine may not recover from an interruption in time to prevent the OS from suspending the app.
- **Fix:** Remove `@MainActor`. Perform engine setup and health-check on a dedicated serial queue (or use `AVAudioEngine`'s internal thread and a simple `Timer` on a background `RunLoop`).
- **Status:** Not fixed.

### #H5 — `IDeviceService` Lacks Reconnection / Retry Logic
- **Severity:** High
- **Phase:** Phase 4
- **Location:** `LocationSimulator/Services/IDeviceService.swift`
- **Problem:** If the tunnel drops (device sleeps, Wi-Fi changes, RSD handshake timeout), `isConnected` flips to `false` but there is no automatic retry, no exposed error to the UI, and no exponential backoff. The user must manually re-import the pairing file and tap Connect again.
- **Fix:** Add a `reconnectAttempts: Int` counter, publish tunnel errors via `@Published var lastError: Error?`, and optionally attempt one automatic reconnect with a 2-second delay before surfacing failure to the user.
- **Status:** Not implemented.

### #H6 — No `LocationSimService` Injection into `RoutePlayer`
- **Severity:** High
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Services/RoutePlayer.swift`
- **Problem:** `RoutePlayer` interpolates coordinates and computes bearing, but the `tick()` method does not appear to call into `LocationSimService.setLocation()`. The simulated coordinate is only published to SwiftUI via `@Published`. The actual system-wide spoofing pipeline is not wired end-to-end.
- **Fix:** Inject `LocationSimService` into `RoutePlayer` (or have `MapViewModel` observe `routePlayer.currentCoordinate` and proxy to the sim service). Ensure every tick sends the coordinate through `location_simulation_set`.
- **Status:** Not wired.

---

## Medium Issues (Incomplete Features / Degraded UX)

### #M1 — `NavigationView` Used Instead of `NavigationStack`
- **Severity:** Medium
- **Phase:** Phase 7
- **Location:** `LocationSimulator/Views/PairingFileImportView.swift` (inferred)
- **Problem:** `NavigationView` is deprecated in iOS 16+. Using it may trigger runtime warnings and will not support programmatic navigation via `NavigationPath`.
- **Fix:** Replace with `NavigationStack` and a `NavigationPath` binding if deep-linking or programmatic dismissal is needed.
- **Status:** Not fixed.

### #M2 — `LocationSimulatorApp` Missing Lifecycle Handling
- **Severity:** Medium
- **Phase:** Phase 6
- **Location:** `LocationSimulator/App/LocationSimulatorApp.swift`
- **Problem:** There is no `scenePhase` observation. When the app moves to background, the tunnel may be torn down by the OS, and when foregrounded, the user must manually reconnect. Similarly, background audio may not restart if the engine was interrupted.
- **Fix:** Add `.onChange(of: scenePhase)` to trigger tunnel health checks and restart silent audio when returning to `.active`.
- **Status:** Not implemented.

### #M3 — Settings Tab Is a Placeholder
- **Severity:** Medium
- **Phase:** Phase 7
- **Location:** `LocationSimulator/Views/ContentView.swift` (Settings tab)
- **Problem:** The Settings tab exists in the `TabView` but contains no actual controls for base URL, cache clearing, speed unit preference (mph/kph), or pairing file re-import.
- **Fix:** Implement `SettingsView` with `Form` sections for Server (OSRM base URL), Simulation (units, default profile), and Data (clear cache, re-import pairing file).
- **Status:** Placeholder only.

### #M4 — Speed Gradient UI Controls Missing
- **Severity:** Medium
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Views/ContentView.swift` / `SimulateTabView`
- **Problem:** `SpeedProfile` enum defines `.gradient(start: end:)`, but the UI only shows a picker for `.walking`, `.biking`, `.driving`, `.custom`. There is no interface to set per-segment speed gradients between two route coordinates.
- **Fix:** Add an "Edit Speeds" sheet that lists route segments with steppers or sliders to adjust speed per segment, then constructs a `.gradient` profile.
- **Status:** Not implemented.

### #M5 — Custom Speed Input Lacks a Numeric Field
- **Severity:** Medium
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Views/ContentView.swift` / `SimulateTabView`
- **Problem:** When `.custom` speed profile is selected, there is no visible `TextField` or slider to input a specific m/s value. The user cannot define a precise custom speed.
- **Fix:** Conditionally show a `TextField("Speed (m/s)", value: $customSpeed, format: .number)` when `.custom` is selected.
- **Status:** Not implemented.

### #M6 — `OSRMRouteService` Has No Base URL Configurability
- **Severity:** Medium
- **Phase:** Phase 3
- **Location:** `LocationSimulator/Services/OSRMRouteService.swift`
- **Problem:** The base URL is likely hardcoded (or defaulted) to a public OSRM demo server. If that server is rate-limited or down, the app cannot route. Users in regions with poor connectivity to the demo server will have a degraded experience.
- **Fix:** Inject `baseURL: URL` via the actor initializer and fall back to the demo server only if nil. Wire it to the Settings tab.
- **Status:** Not verified / likely hardcoded.

### #M7 — `TimedRoute` and `RoutePlayer` Do Not Account for Traffic Light Variance
- **Severity:** Medium
- **Phase:** Phase 5
- **Location:** `LocationSimulator/Services/RoutePlayer.swift`
- **Problem:** `TrafficControlType.trafficLight(averageDuration:variance:)` stores a variance, but `RoutePlayer.tick()` appears to use a fixed pause duration. The stochastic delay (average ± variance) is not sampled from a distribution.
- **Fix:** On first encounter of a traffic light, sample `actualDelay = Double.random(in: average-variance ... average+variance)` and store it in `processedControlIDs` (or a parallel dictionary) so the same light isn't re-sampled on subsequent ticks.
- **Status:** Not implemented.

---

## Low Issues (Polish / Accessibility / Testing)

### #L1 — Limited Unit Test Coverage
- **Severity:** Low
- **Phase:** Phase 8
- **Location:** `LocationSimulatorTests/`
- **Problem:** Only `OSRMRouteServiceTests.swift` exists. There are no tests for `RoutePlayer`, `IDeviceService`, `GPXParser`, `SpeedProfileEngine`, `LocationSimService`, or the VPN packet rewriter.
- **Fix:** Add tests for:
  - `RoutePlayer` tick interpolation and traffic control pausing (inject a mock `LocationSimService`).
  - `GPXParser` round-trip (parse then re-serialise).
  - `SpeedProfileEngine` gradient computation.
  - `PacketTunnelProvider` IPv4 checksum recomputation against known test vectors.
- **Status:** Not started.

### #L2 — Missing Accessibility Labels on Map Overlay Buttons
- **Severity:** Low
- **Phase:** Phase 7
- **Location:** `LocationSimulator/Views/MapView.swift`
- **Problem:** The HStack overlay buttons (Route, Stop, Light, Clear) rely on `Label(text, systemImage:)` which provides a default label, but VoiceOver may not clearly distinguish the disabled vs enabled states. There are no `.accessibilityHint` or `.accessibilityValue` modifiers.
- **Fix:** Add `.accessibilityLabel()`, `.accessibilityHint()`, and `.accessibilityValue()` to each control, describing what the button does and whether it is currently available.
- **Status:** Not implemented.

### #L3 — `MapView` Pin Overlap Handling Not Implemented
- **Severity:** Low
- **Phase:** Phase 7
- **Location:** `LocationSimulator/Views/MapView.swift`
- **Problem:** If start and end pins are placed very close together, or a traffic control sits directly on a route node, the annotations overlap visually. There is no clustering, offset, or selection mechanism to disambiguate.
- **Fix:** Use `Map` annotation clustering or add a small random offset to traffic controls so they don't perfectly overlap with route coordinates.
- **Status:** Not implemented.

### #L4 — No Dark Mode Specific Map Styling
- **Severity:** Low
- **Phase:** Phase 7
- **Location:** `LocationSimulator/Views/MapView.swift`
- **Problem:** The map style is fixed to `.standard(elevation: .realistic, showsTraffic: true)`. It does not adapt to the system dark mode appearance.
- **Fix:** Use `.standard(elevation: .realistic, showsTraffic: true, emphasis: .automatic)` or switch to `.hybrid` / `.imagery` based on `colorScheme` environment value.
- **Status:** Not implemented.

---

## What Was Not Added (Plan v2 Gaps)

| Planned Feature | Phase | Status | Notes |
|-----------------|-------|--------|-------|
| RPPairing file generation helper UI | 1 | Missing | No view to guide the user through extracting the pairing plist from StikDebug or a Mac. |
| VPN extension target & entitlements | 2 | Missing | `project.yml` lacks the extension. `LocationSimulator.entitlements` may also lack `com.apple.developer.networking.networkextension` if not manually added. |
| Packet tunnel IPv6 support | 2 | Missing | Only IPv4 header rewriting is implemented. RSD can use IPv6 in some network configurations. |
| OSRM route alternatives / snapping | 3 | Missing | No `alternatives=true` parameter or waypoint snapping UI. |
| GPX export from recorded route | 5 | Missing | `SimulateTabView` mentions GPX import/export but export may not serialize the actual played route with timestamps. |
| Speed unit conversion (mph/kph) | 7 | Missing | All internal speeds are m/s; no UI conversion layer. |
| Transparency / disclosure view for `isSimulatedBySoftware` | 7 | Missing | The plan explicitly asked for an educational sheet explaining that iOS 15+ flags developer-simulated locations. No such sheet exists. |
| E2E UI tests for route generation flow | 8 | Missing | No XCUITest target in `project.yml`. |
| CI artifact distribution (IPA export) | 9 | Missing | CI only builds; it does not archive, export, or upload an `.ipa` for sideloading. |
| Automated `libidevice_ffi.a` build in CI | 9 | Missing | CI assumes the binary is present; no Rust toolchain setup step exists. |

---

## Recommended Fix Order

1. **Fix `project.yml` deployment target** (#C1) — one-line change.
2. **Fix CI Xcode version** (#C3) — one-line change.
3. **Add VPN extension target to `project.yml`** (#C2) — requires understanding XcodeGen extension syntax.
4. **Obtain or build `libidevice_ffi.a`** (#C4) — the biggest blocker. Consider using `cargo-zigbuild` or `cargo-lipo` to produce a universal iOS static library.
5. **Verify `idevice.h` against actual Rust exports** (#C5) — run `nm` once #C4 is done.
6. **Wire `LocationSimService` into `RoutePlayer`** (#H6) — without this, route playback is purely cosmetic.
7. **Replace unbounded OSRM cache with `NSCache`** (#H1) — prevents OOM during long sessions.
8. **Rewrite `GPXParser` with `XMLParser`** (#H2) — correctness improvement.
9. **Add lifecycle handling to `LocationSimulatorApp`** (#M2) — improves background resilience.
10. **Implement Settings tab** (#M3), **speed gradient UI** (#M4), and **custom speed input** (#M5) — closes the remaining medium gaps.
11. **Add transparency sheet** (Plan v2 Phase 7 gap) — required for App Store / sideloading ethical disclosure.
12. **Expand unit tests** (#L1) — begin with `RoutePlayer` mock injection.

---

## Environment & Build Prerequisites

- **Xcode:** 15.4+ (Swift 5.9)
- **iOS Deployment Target:** 17.4 (RPPairing requirement)
- **Rust Toolchain:** Required to build `jkcoxson/idevice` for iOS (`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`)
- **XcodeGen:** `brew install xcodegen`
- **Entitlements:** `com.apple.developer.networking.networkextension` must be present in the App ID provisioning profile for VPN extension sideloading.

---

## Open Questions for Next Session

1. What is the exact commit hash or tag of `jkcoxson/idevice` that this project targets? The FFI signatures in `idevice.h` must match that exact version.
2. Is the `VPN/` directory intended to be a separate App Extension target, or was it meant to be compiled into the main app binary? `NEPacketTunnelProvider` must live in an extension.
3. Does the user have an Apple Developer account with the Network Extension entitlement, or is sideloading via SideStore/AltStore the only distribution path? This affects provisioning profile setup.
4. What is the preferred OSRM server? The public demo server (`router.project-osrm.org`) has strict rate limits and CORS policies that may not work from an iOS app without a proxy.
