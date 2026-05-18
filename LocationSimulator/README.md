# LocationSimulator

LocationSimulator is an iOS app that lets you simulate GPS movement along custom routes. Drop start and end pins, generate a driving route, and watch your location move in real-time inside Apple Maps or any location-aware app.

## Features

- **Route Planning**: Drop start/end pins on an interactive map and generate optimized driving routes.
- **Traffic Simulation**: Add traffic lights, stop signs, and speed profiles (Walking / Cycling / Driving) for realistic pacing.
- **Background Simulation**: Continues simulating location even when the app is backgrounded using silent audio and background location APIs.
- **VPN-Based Location Injection**: Uses a local VPN extension (LocalDevVPN) to inject simulated coordinates at the system level so Maps and other apps see the fake location.
- **Pairing-Free (iOS 17.4+)**: Leverages `RPPairing` and `libidevice` for on-device pairing file generation, eliminating the need for a Mac after initial setup.
- **Route Import / Export**: Save and share routes as GPX files.

## Requirements

- **iOS**: 17.4 or later
- **Developer Mode**: Must be enabled in Settings -> Privacy & Security
- **Sideloading Tool**: SideStore or AltStore (see [DISTRIBUTION.md](DISTRIBUTION.md))
- **Apple ID**: Free or paid developer account

## Quick Start

1. **Sideload the IPA** using SideStore or AltStore (see [DISTRIBUTION.md](DISTRIBUTION.md)).
2. **Generate a pairing file** with JitterbugPair on your computer and transfer it to the device.
3. **Open LocationSimulator**, import the pairing file, and grant location permissions.
4. **Enable LocalDevVPN** in Settings -> VPN or via the in-app toggle.
5. **Drop pins** on the map to set a start and end point.
6. **Tap "Generate Route"** to fetch a driving path from OSRM.
7. **Tap "Start Simulation"** and watch your location move in Apple Maps.

## Architecture Overview

```
LocationSimulator/
├── App/                        # App entry point (AppDelegate, SceneDelegate)
├── Views/                      # SwiftUI views (Map, Route, Simulation)
├── ViewModels/                 # Observable state and business logic
├── Models/                     # Route, Pin, GPX, Config models
├── Services/                   # LocationManager, GPXService, AudioManager
├── VPN/                        # NetworkExtension target (LocalDevVPN)
├── idevice/                    # libidevice FFI headers and static libs
├── scripts/                    # build_ipa.sh, exportOptions.plist
└── Resources/                  # Assets, Config.plist, Info.plist
```

- **Frontend**: SwiftUI with MapKit.
- **Location Injection**: `CLLocationManager` override inside a `NEPacketTunnelProvider` VPN extension.
- **Device Communication**: `libidevice` C library bridged via FFI for pairing and location simulation.
- **Routing**: Open Source Routing Machine (OSRM) via public or self-hosted server.

## Building from Source

1. Clone the repository.
2. Open `LocationSimulator.xcodeproj` in Xcode 15+.
3. Replace `YOUR_TEAM_ID` and provisioning profile placeholders in `scripts/exportOptions.plist` with your own Apple Developer credentials.
4. Select your development team and signing certificates in Xcode.
5. Run the app on a physical device (iOS Simulator does not support VPN extensions or location simulation).
6. To produce a release IPA:
   ```bash
   cd LocationSimulator
   chmod +x scripts/build_ipa.sh
   ./scripts/build_ipa.sh
   ```
   The resulting IPA will be at `build/ipa/LocationSimulator.ipa`.

## License & Disclaimer

This project is provided for educational and development purposes only. Simulating location may violate the terms of service of third-party apps. Use responsibly and only in environments where you have permission to do so. The authors assume no liability for misuse.
