import SwiftUI
import CoreLocation

struct TransparencyView: View {
    @ObservedObject var routePlayer: RoutePlayer

    private var isSimulating: Bool {
        routePlayer.state != .idle && routePlayer.state != .completed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isSimulating {
                    VStack(spacing: 8) {
                        Text("isSimulatedBySoftware == true")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                        Text("Simulation is currently active")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Spoofed Coordinate")
                        .font(.headline)

                    if let coord = routePlayer.currentCoordinate {
                        Label(
                            String(format: "%.6f, %.6f", coord.latitude, coord.longitude),
                            systemImage: "location.fill"
                        )
                        .font(.body.monospaced())

                        Label(
                            String(format: "%.1f m/s", routePlayer.currentSpeed),
                            systemImage: "speedometer"
                        )
                        .font(.body.monospaced())
                    } else {
                        Text("No active simulation")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("How Detection Works")
                        .font(.headline)

                    Text("Apps that check CLLocationSourceInformation will see the simulated flag. This is an intentional Apple developer feature, not a stealth bypass.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Detection Vectors")
                        .font(.headline)

                    detectionVectorRow(
                        icon: "checkmark.shield",
                        title: "isSimulatedBySoftware flag",
                        detail: "iOS 15+ exposes this boolean in CLLocationSourceInformation."
                    )

                    detectionVectorRow(
                        icon: "bolt.fill",
                        title: "Impossible GPS jumps",
                        detail: "Instantaneous teleportation between distant coordinates."
                    )

                    detectionVectorRow(
                        icon: "wifi.slash",
                        title: "Wi-Fi BSSID / cell tower mismatch",
                        detail: "Simulated coordinates may not match visible network infrastructure."
                    )

                    detectionVectorRow(
                        icon: "iphone",
                        title: "Accelerometer inconsistency",
                        detail: "Device motion sensors may disagree with reported location changes."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Text("This tool uses Apple's developer location simulation service. Third-party apps can detect simulated locations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Transparency")
    }

    private func detectionVectorRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    let ds = IDeviceService()
    let lss = LocationSimService(deviceService: ds)
    TransparencyView(routePlayer: RoutePlayer(locationSimService: lss))
}
