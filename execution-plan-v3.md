# LocationSimulator — Execution Plan v3

> Based on: `location-simulator-plan-v2.md`, `ISSUES_AUDIT.md`, and research into jkcoxson/idevice v0.1.62 + XcodeGen extension syntax.
> Date: 2026-05-18

---

## Phase 0: Documentation Discovery (Complete)

### Allowed APIs / Verified Patterns

| Source | Finding |
|--------|---------|
| jkcoxson/idevice v0.1.62 | Pre-built `idevice-xcframework-v0.1.62.zip` available. Uses `com.apple.instruments.server.services.LocationSimulation`. RPPairing port 49152 confirmed. |
| XcodeGen ProjectSpec.md | `type: app-extension` for iOS VPN extensions. `embed: true` to embed in host app. `NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel`. |
| Apple TN3134 | Entitlement string is `packet-tunnel-provider` (not `packet-tunnel`). Both app + extension need it. |
| GitHub Actions runner-images | `macos-26` runner has Xcode 26.5. `xcode-version: '26.5'` is the correct string for setup-xcode. |

### Anti-Patterns to Avoid
- Do NOT use `com.apple.dt.simulatelocation` — the library uses the Instruments service path.
- Do NOT use `type: system-extension` — that's macOS only. iOS VPN = `app-extension`.
- Do NOT hardcode port 62078 (legacy lockdown). Use 49152 or mDNS-discovered RPPairing port.
- Do NOT assume TSS/DDI mounting works on iOS 26.5 — it has a known regression. Location simulation itself is unaffected.

---

## Phase 1: Fix Build Blockers (C1, C2, C3, C4)

### 1.1 Fix `project.yml` deployment target
**What:** Change `deploymentTarget: "26.5"` → `"17.4"`.
**Why:** Broader compatibility while still running on iOS 26.5. RPPairing requires 17.4+.
**Verification:** `xcodegen generate` succeeds without platform version errors.

### 1.2 Fix CI Xcode version
**What:** Change `.github/workflows/ios.yml` `xcode-version: '26.3'` → `'26.5'`.
**Why:** Match the actual Xcode version that ships iOS 26.5 SDK. Use `macos-26` runner.
**Verification:** `setup-xcode` step passes in CI.

### 1.3 Add VPN extension target to `project.yml`
**What:** Add `LocationSimulatorVPN` target (`type: app-extension`, platform iOS, sources: `VPN/`).
**Why:** `NEPacketTunnelProvider` must live in an embedded extension.
**Verification:** `xcodegen generate` produces an extension target; `xcodebuild` compiles it.

### 1.4 Obtain `libidevice` binary
**What:** Download `idevice-xcframework-v0.1.62.zip` from jkcoxson/idevice releases, extract the iOS static library / xcframework, place in `LocationSimulator/idevice/`.
**Why:** Eliminates the need to compile Rust. The xcframework includes arm64 + x86_64 slices.
**Verification:** `xcodebuild` links successfully; `nm` shows expected symbols.

### 1.5 Verify `idevice.h` against xcframework exports
**What:** Run `nm` on the extracted static library, compare against `idevice.h` declarations.
**Why:** Ensure FFI signatures match to prevent runtime crashes.
**Verification:** All functions in `idevice.h` resolve to symbols in the binary.

---

## Phase 2: Wire Core Services (H6, H5)

### 2.1 Connect `RoutePlayer` → `LocationSimService`
**What:** Inject `LocationSimService` into `RoutePlayer`; call `setLocation` on every tick.
**Why:** Without this, route playback is purely cosmetic.
**Verification:** Unit test mocks `LocationSimService` and asserts `setLocation` is called with interpolated coordinates.

### 2.2 Add `IDeviceService` reconnect logic
**What:** Exponential backoff retry (max 3 attempts), publish errors via `@Published`.
**Why:** Tunnel drops on sleep/Wi-Fi change are common.
**Verification:** Disconnect tunnel mid-playback; observe auto-reconnect within 5 seconds.

---

## Phase 3: Fix Runtime Risks (H1, H2, H3, H4)

### 3.1 Replace unbounded OSRM cache with `NSCache`
**What:** Convert `Dictionary` cache to `NSCache` with cost-based eviction.
**Why:** Prevents OOM during long sessions.
**Verification:** Generate 100+ routes; memory stays bounded.

### 3.2 Rewrite `GPXParser` with `XMLParser`
**What:** Replace regex with Foundation `XMLParser` for robust GPX parsing.
**Why:** Regex breaks on namespaces, CDATA, comments.
**Verification:** Parse GPX files with namespaces and CDATA; all trackpoints extracted.

### 3.3 Defensive `playbackMultiplier` clamping
**What:** Make multiplier a computed property with `didSet` clamp.
**Why:** Prevents UI bindings or external code from setting invalid values.
**Verification:** Set multiplier to -1 and 100; both clamp to 0.1 and 10.0.

### 3.4 Remove `@MainActor` from `BackgroundAudioManager`
**What:** Run audio engine on a dedicated serial queue.
**Why:** Main-actor audio I/O can block UI and fail to recover from interruptions.
**Verification:** Background audio survives 30+ seconds in background without main-thread stalls.

---

## Phase 4: Close Medium UI Gaps (M2, M3, M4, M5, M6, M7)

### 4.1 App lifecycle handling
**What:** Add `.onChange(of: scenePhase)` to restart tunnel/audio on foreground.
**Verification:** Background the app for 60s, foreground it; tunnel reconnects automatically.

### 4.2 Settings tab implementation
**What:** `Form` with OSRM base URL, speed units, cache clear, pairing file re-import.
**Verification:** Settings values persist via `@AppStorage`; base URL change reflects in next route request.

### 4.3 Speed gradient UI
**What:** Sheet listing route segments with per-segment speed steppers.
**Verification:** Select `.gradient`, set two segments to different speeds, play route; speeds interpolate correctly.

### 4.4 Custom speed input
**What:** Numeric `TextField` visible when `.custom` profile selected.
**Verification:** Enter 15.5 m/s, start simulation; `RoutePlayer.currentSpeed` reads 15.5.

### 4.5 Configurable OSRM base URL
**What:** Inject URL into `OSRMRouteService` actor, default to public demo.
**Verification:** Change base URL in Settings; route requests hit the new endpoint.

### 4.6 Traffic light variance sampling
**What:** Sample delay from `average ± variance` on first encounter, store in dictionary.
**Verification:** Add traffic light with average 45s, variance 15s; observed pauses vary between 30-60s.

---

## Phase 5: Polish (M1, L1, L2, L3, L4)

### 5.1 Replace `NavigationView` with `NavigationStack`
**Verification:** No deprecation warnings; programmatic navigation works.

### 5.2 Expand unit tests
**What:** `RoutePlayer` mock injection, `GPXParser` round-trip, `SpeedProfileEngine`, packet checksum.
**Verification:** Test suite passes with >80% coverage on core services.

### 5.3 Accessibility labels
**What:** Add `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue` to map controls.
**Verification:** VoiceOver reads clear descriptions for Route/Stop/Light/Clear buttons.

### 5.4 Map dark mode
**What:** Switch map style based on `colorScheme` environment.
**Verification:** Map renders in dark mode when system appearance is dark.

---

## Phase 6: Transparency & Distribution (Plan v2 Gaps)

### 6.1 Add `isSimulatedBySoftware` disclosure sheet
**What:** Educational sheet explaining iOS 15+ developer-simulation flagging.
**Verification:** Sheet presents on first launch and is accessible from Settings.

### 6.2 CI IPA export
**What:** Add archive + export steps to GitHub Actions, upload `.ipa` artifact.
**Verification:** CI produces a downloadable `.ipa` for sideloading.

---

## Execution Order

| Order | Phase | Items | Why First |
|-------|-------|-------|-----------|
| 1 | Phase 1.1-1.2 | Fix deployment target, CI Xcode | One-line changes, unblock CI immediately |
| 2 | Phase 1.3 | Add VPN extension target | Required for tunnel functionality |
| 3 | Phase 1.4-1.5 | Obtain libidevice, verify header | The real build blocker; xcframework eliminates Rust compile step |
| 4 | Phase 2.1 | Wire RoutePlayer → LocationSimService | Core feature without which the app doesn't spoof |
| 5 | Phase 2.2 | Reconnect logic | Reliability improvement |
| 6 | Phase 3.x | Runtime risk fixes | Prevents crashes/bugs in normal use |
| 7 | Phase 4.x | UI gap closure | Feature completeness |
| 8 | Phase 5.x | Polish | Quality before distribution |
| 9 | Phase 6.x | Transparency + IPA export | Final delivery |
