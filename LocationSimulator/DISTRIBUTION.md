# Distribution Guide

This document explains how to install LocationSimulator on a physical iOS device using sideloading tools.

## Table of Contents

- [SideStore Installation](#sidestore-installation)
- [AltStore Installation](#altstore-installation)
- [JitterbugPair (One-Time Computer Step)](#jitterbugpair-one-time-computer-step)
- [Paid Developer Account](#paid-developer-account)
- [EU Users (iOS 17.4+)](#eu-users-ios-174)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)

---

## SideStore Installation

[SideStore](https://sidestore.io) is a fork of AltStore that allows on-device sideloading without requiring AltServer to be running on your computer after initial setup.

1. **Install AltServer** on your Mac or Windows PC from [altstore.io](https://altstore.io).
2. **Install SideStore** on your iOS device using AltServer.
3. **Pair your device** with your computer via USB. Trust the computer when prompted.
4. **Sideload the IPA**:
   - Open SideStore on your device.
   - Tap the "+" button and select the `LocationSimulator.ipa` file.
   - Wait for installation to complete.
5. **Refresh the app** every 7 days (free Apple ID) or once per year (paid Apple Developer account).

## AltStore Installation

If you prefer the original AltStore workflow:

1. **Install AltServer** on your computer from [altstore.io](https://altstore.io).
2. **Install AltStore** on your iOS device via AltServer.
3. **Connect your device** to the same Wi-Fi network as your computer (or keep it connected via USB).
4. **Sideload the IPA**:
   - Open AltStore on your device.
   - Tap the "My Apps" tab, then the "+" button.
   - Select `LocationSimulator.ipa` and wait for installation.
5. **Refresh** the app before the 7-day free-certificate expiry. AltServer must be running on your computer during refresh.

## JitterbugPair (One-Time Computer Step)

LocationSimulator uses `libidevice` to communicate with iOS location services. A pairing file is required.

1. **Download JitterbugPair** from the [Jitterbug releases page](https://github.com/osy/Jitterbug/releases) (or build from source).
2. **Connect your iOS device to your computer via USB**.
3. **Run JitterbugPair**:
   ```bash
   ./JitterbugPair
   ```
   This generates `rp_pairing_file.plist` in the same directory.
4. **Transfer the file to your device**:
   - AirDrop the `.plist` to your iPhone, or
   - Save it to iCloud Drive / Files, or
   - Send it via messaging app.
5. **In LocationSimulator**, tap "Import Pairing File" and select `rp_pairing_file.plist`. You only need to do this once per device.

## Paid Developer Account

If you have a paid Apple Developer Account ($99/year), you can avoid the 7-day refresh cycle and the 3-app limit.

1. **Register your device UDID** in the [Apple Developer Portal](https://developer.apple.com/account/resources/devices/list).
2. **Create provisioning profiles**:
   - One for the main app bundle ID (`com.yourcompany.locationsimulator`).
   - One for the VPN extension bundle ID (`com.yourcompany.locationsimulator.vpn`).
3. **Download** both `.mobileprovision` files and place them in the project directory (they are ignored by `.gitignore`).
4. **Update `scripts/exportOptions.plist`** with your Team ID and provisioning profile names.
5. **Build and sign** the IPA using `scripts/build_ipa.sh`. The resulting IPA will be valid for **1 year**.

## EU Users (iOS 17.4+)

Apple introduced support for third-party app marketplaces in the EU starting with iOS 17.4. As these marketplaces mature, LocationSimulator may become available through an approved alternative marketplace, eliminating the need for manual sideloading. This remains a future option; for now, SideStore or AltStore is recommended.

## Limitations

- **7-day expiry**: Free Apple Developer accounts must refresh sideloaded apps every 7 days.
- **3-app limit**: Free accounts are limited to 3 active sideloaded apps at a time (including SideStore/AltStore itself).
- **Developer Mode required**: iOS 16+ requires Developer Mode to be enabled in Settings -> Privacy & Security.
- **iOS 17.4+ required for RPPairing**: On-device pairing file generation and the VPN-based location pipeline require iOS 17.4 or later. Older versions require a wired Mac connection and Xcode-based location simulation.
- **Physical device only**: The VPN NetworkExtension does not run in the iOS Simulator.

## Troubleshooting

### VPN does not connect
- Verify that the VPN extension provisioning profile is correctly signed.
- Check `LocationSimulator.entitlements` includes `com.apple.developer.networking.networkextension`.
- Ensure you have granted VPN permission in Settings -> VPN when prompted.

### Location is not simulating
- Confirm the pairing file (`rp_pairing_file.plist`) has been imported successfully.
- Verify that LocalDevVPN is toggled ON in Settings -> VPN.
- Make sure **Developer Mode** is enabled in Settings -> Privacy & Security.
- Check that the device is running iOS 17.4 or later.

### App crashes on launch
- Confirm the device is on iOS 17.4+ (the app checks for `RPPairing` APIs).
- Re-sign the IPA with valid provisioning profiles and reinstall.
- If using a free account, ensure the app was refreshed within the last 7 days.

### SideStore / AltStore refresh fails
- Ensure your device is on the same Wi-Fi as your computer (AltStore) or that SideStore's wireguard tunnel is active (SideStore).
- Sign out and back into your Apple ID within the store app.
- Re-install the store app via AltServer if the certificate has expired.
