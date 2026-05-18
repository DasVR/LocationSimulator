import SwiftUI
import CoreLocation
import Combine
import NetworkExtension

/// Simple wrapper around CLLocationManager to expose the real device location for debug overlay.
class LocationManagerWrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.lastLocation = locations.last
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
}

struct DebugOverlayView: View {
    @ObservedObject var routePlayer: RoutePlayer
    @ObservedObject var vpnManager: VPNManager
    @StateObject private var locationWrapper = LocationManagerWrapper()

    @State private var isSimulationExpanded = true
    @State private var isLocationExpanded = true
    @State private var isNetworkExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                simulationSection
                locationSection
                networkSection
            }
            .padding()
        }
        .navigationTitle("Debug Overlay")
        .onAppear {
            locationWrapper.requestAuthorization()
            locationWrapper.startUpdates()
        }
        .onDisappear {
            locationWrapper.stopUpdates()
        }
    }

    private var simulationSection: some View {
        DisclosureGroup(isExpanded: $isSimulationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                debugRow(label: "State", value: String(describing: routePlayer.state))

                if let coord = routePlayer.currentCoordinate {
                    debugRow(label: "Simulated Lat", value: String(format: "%.6f", coord.latitude))
                    debugRow(label: "Simulated Lon", value: String(format: "%.6f", coord.longitude))
                } else {
                    debugRow(label: "Simulated Coordinate", value: "—")
                }

                debugRow(label: "Speed", value: String(format: "%.1f m/s", routePlayer.currentSpeed))
                debugRow(label: "Course", value: String(format: "%.1f°", routePlayer.currentCourse))
                debugRow(label: "Progress", value: String(format: "%.1f%%", routePlayer.progressRatio * 100))
                debugRow(label: "Playback Multiplier", value: String(format: "%.1fx", routePlayer.playbackMultiplier))

                if let dist = routePlayer.nextNodeDistance {
                    debugRow(label: "Next Waypoint", value: String(format: "%.0f m", dist))
                } else {
                    debugRow(label: "Next Waypoint", value: "—")
                }

                if let control = routePlayer.nextTrafficControl {
                    let dist = routePlayer.nextTrafficControlDistance ?? 0
                    debugRow(label: "Next Traffic Control", value: "\(control.type.displayName) (\(String(format: "%.0f", dist)) m)")
                } else {
                    debugRow(label: "Next Traffic Control", value: "—")
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Simulation", systemImage: "play.circle.fill")
                .font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var locationSection: some View {
        DisclosureGroup(isExpanded: $isLocationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let loc = locationWrapper.lastLocation {
                    debugRow(label: "Real Lat", value: String(format: "%.6f", loc.coordinate.latitude))
                    debugRow(label: "Real Lon", value: String(format: "%.6f", loc.coordinate.longitude))
                    debugRow(label: "Real Accuracy", value: String(format: "%.1f m", loc.horizontalAccuracy))
                } else {
                    Text("Waiting for real location…")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Real Location", systemImage: "location.circle.fill")
                .font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var networkSection: some View {
        DisclosureGroup(isExpanded: $isNetworkExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                debugRow(label: "VPN Status", value: vpnStatusString(vpnManager.status))
                debugRow(label: "Tunnel Connected", value: vpnManager.isConnected ? "Yes" : "No")
            }
            .padding(.top, 8)
        } label: {
            Label("Network", systemImage: "network.badge.shield.half.filled")
                .font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func debugRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private func vpnStatusString(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    let ds = IDeviceService()
    let lss = LocationSimService(deviceService: ds)
    DebugOverlayView(routePlayer: RoutePlayer(locationSimService: lss), vpnManager: VPNManager())
}
