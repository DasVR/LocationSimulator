import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var mapViewModel = MapViewModel()
    @StateObject private var deviceService: IDeviceService
    @StateObject private var vpnManager: VPNManager
    @StateObject private var routePlayer: RoutePlayer

    init() {
        let ds = IDeviceService()
        let lss = LocationSimService(deviceService: ds)
        _deviceService = StateObject(wrappedValue: ds)
        _vpnManager = StateObject(wrappedValue: VPNManager())
        _routePlayer = StateObject(wrappedValue: RoutePlayer(locationSimService: lss))
    }

    var body: some View {
        TabView {
            MapTabView(viewModel: mapViewModel)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            SimulateTabView(routePlayer: routePlayer, mapViewModel: mapViewModel)
                .tabItem {
                    Label("Simulate", systemImage: "location.circle")
                }

            TransparencyView(routePlayer: routePlayer)
                .tabItem {
                    Label("Transparency", systemImage: "eye")
                }

            DebugOverlayView(routePlayer: routePlayer, vpnManager: vpnManager)
                .tabItem {
                    Label("Debug", systemImage: "ant.fill")
                }

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct MapTabView: View {
    var viewModel: MapViewModel

    var body: some View {
        MapView(viewModel: viewModel)
    }
}

struct SimulateTabView: View {
    @ObservedObject var routePlayer: RoutePlayer
    var mapViewModel: MapViewModel

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var selectedProfile: SpeedProfile = .driving
    @State private var importError: Error?
    @State private var showImportError = false
    @State private var exportData: Data?
    @State private var showNoRouteAlert = false

    private let engine = SpeedProfileEngine()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Simulation Controls")
                    .font(.largeTitle)
                    .padding(.top)

                if routePlayer.state == .idle || routePlayer.state == .completed {
                    VStack(spacing: 16) {
                        Picker("Speed Profile", selection: $selectedProfile) {
                            ForEach(Array(SpeedProfile.allCases.enumerated()), id: \.offset) { _, profile in
                                Text(profile.displayName).tag(profile)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            isImporting = true
                        } label: {
                            Label("Import GPX Route", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            exportRoute()
                        } label: {
                            Label("Export Current Route", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(mapViewModel.routeCoordinates.isEmpty)

                        if let timedRoute = mapViewModel.timedRoute {
                            Button {
                                routePlayer.start(
                                    route: timedRoute,
                                    trafficControls: mapViewModel.trafficControls,
                                    playbackMultiplier: 1.0
                                )
                            } label: {
                                Label("Start Simulation", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("Simulation \(routePlayer.state == .running ? "Running" : "Paused")")
                            .font(.headline)

                        if let coord = routePlayer.currentCoordinate {
                            Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                                .font(.body.monospaced())
                        }

                        HStack(spacing: 16) {
                            if routePlayer.state == .running {
                                Button("Pause") {
                                    routePlayer.pause()
                                }
                                .buttonStyle(.borderedProminent)
                            } else if routePlayer.state == .paused {
                                Button("Resume") {
                                    routePlayer.resume()
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button("Stop") {
                                routePlayer.stop()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                }

                Spacer()
            }
            .padding()
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType.xml],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: GPXDocument(data: exportData ?? Data()),
                contentType: UTType.xml,
                defaultFilename: "route.gpx"
            ) { _ in
                // Export completed
            }
            .alert("Import Error", isPresented: $showImportError, presenting: importError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .alert("No Route", isPresented: $showNoRouteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There is no current route to export.")
            }
            .navigationTitle("Simulate")
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let coordinates = try GPXParser.parse(data: data)

            let profile = selectedProfile
            let rp = routePlayer
            Task {
                let timedRoute = await engine.computeTimedRoute(coordinates: coordinates, profile: profile)
                await MainActor.run {
                    rp.start(route: timedRoute, playbackMultiplier: 1.0)
                }
            }
        } catch {
            importError = error
            showImportError = true
        }
    }

    private func exportRoute() {
        guard !mapViewModel.routeCoordinates.isEmpty else {
            showNoRouteAlert = true
            return
        }
        let gpxString = GPXExporter.export(coordinates: mapViewModel.routeCoordinates)
        exportData = gpxString.data(using: .utf8)
        isExporting = true
    }
}

struct SettingsTabView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
                .padding()
            Text("App configuration will appear here.")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct GPXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ContentView()
}
