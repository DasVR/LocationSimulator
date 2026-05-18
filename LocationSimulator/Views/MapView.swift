import SwiftUI
import MapKit

/// The primary map interface for the LocationSimulator app.
/// Displays the user's location, dropped pins, route polylines,
/// traffic control overlays, and the simulated location.
struct MapView: View {
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var viewModel: MapViewModel

    var body: some View {
        MapReader { proxy in
            ZStack {
                mapContent(proxy: proxy)
                mapOverlay
            }
        }
    }

    private var mapOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.generateRoute()
                    }
                } label: {
                    Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.startCoordinate == nil || viewModel.endCoordinate == nil || viewModel.isGeneratingRoute)
                .tint(.blue)

                Button {
                    if let end = viewModel.endCoordinate {
                        viewModel.addTrafficControl(at: end, type: .stopSign(minimumDuration: 3))
                    }
                } label: {
                    Label("Stop", systemImage: "octagon.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.routeCoordinates.isEmpty)
                .tint(.red)

                Button {
                    if let end = viewModel.endCoordinate {
                        viewModel.addTrafficControl(at: end, type: .trafficLight(averageDuration: 45, variance: 15))
                    }
                } label: {
                    Label("Light", systemImage: "lights.vertical.traffic")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.routeCoordinates.isEmpty)
                .tint(.yellow)

                Button {
                    viewModel.setRoute(coordinates: [])
                    viewModel.clearTrafficControls()
                    viewModel.timedRoute = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)

            if viewModel.isGeneratingRoute {
                ProgressView("Generating route…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }

            if let error = viewModel.routingError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    private func mapContent(proxy: MapProxy) -> some View {
        Map(position: $cameraPosition, showsUserLocation: true) {
                // MARK: - Pins
                ForEach(viewModel.pins) { pin in
                    if case .start = pin.type {
                        Marker("Start", systemImage: "mappin.circle.fill", coordinate: pin.coordinate)
                            .tint(.green)
                    }
                    if case .end = pin.type {
                        Marker("End", systemImage: "mappin.circle.fill", coordinate: pin.coordinate)
                            .tint(.red)
                    }
                    if case .trafficControl(let controlType) = pin.type {
                        Annotation(pin.label, coordinate: pin.coordinate) {
                            TrafficControlAnnotationView(type: controlType)
                        }

                        // Traffic control influence radius
                        MapCircle(
                            center: pin.coordinate,
                            radius: controlType == .stopSign ? 20.0 : 15.0
                        )
                        .foregroundStyle(
                            (controlType == .stopSign ? Color.red : Color.yellow).opacity(0.3)
                        )
                    }
                }

                // MARK: - Route Polyline
                if !viewModel.routeCoordinates.isEmpty {
                    MapPolyline(coordinates: viewModel.routeCoordinates)
                        .stroke(.blue, lineWidth: 4)
                }

                // MARK: - Simulated Location
                if let simulated = viewModel.simulatedCoordinate {
                    Annotation("Simulated Location", coordinate: simulated) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, showsTraffic: true))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { position in
                // Convert the tap point in the MapReader's local coordinate space
                // to a CLLocationCoordinate2D.
                if let coordinate = proxy.convert(position, from: .local) {
                    let hasStart = viewModel.pins.contains { pin in
                        if case .start = pin.type { return true }
                        return false
                    }
                    let hasEnd = viewModel.pins.contains { pin in
                        if case .end = pin.type { return true }
                        return false
                    }

                    if !hasStart {
                        viewModel.addPin(at: .start, coordinate: coordinate)
                    } else if !hasEnd {
                        viewModel.addPin(at: .end, coordinate: coordinate)
                    } else {
                        // Both start and end exist; replace the end pin with the new tap.
                        viewModel.removePins(ofType: .end)
                        viewModel.addPin(at: .end, coordinate: coordinate)
                    }
                }
            }
        }
    }

// MARK: - Traffic Control Annotation

/// Custom SwiftUI content for traffic control annotations.
struct TrafficControlAnnotationView: View {
    let type: TrafficControlType

    var body: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
            .padding(4)
            .background(Circle().fill(.white).shadow(radius: 2))
    }

    private var iconName: String {
        switch type {
        case .stopSign:
            return "octagon.fill"
        case .trafficLight:
            return "lights.vertical.traffic"
        }
    }

    private var iconColor: Color {
        switch type {
        case .stopSign:
            return .red
        case .trafficLight:
            return .yellow
        }
    }
}

#Preview {
    let vm = MapViewModel()
    // Hardcoded test coordinates for preview (San Francisco to San Jose).
    vm.addPin(at: .start, coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
    vm.addPin(at: .end, coordinate: CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863))
    vm.setRoute(coordinates: [
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        CLLocationCoordinate2D(latitude: 37.6879, longitude: -122.4702),
        CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)
    ])
    return MapView(viewModel: vm)
}
