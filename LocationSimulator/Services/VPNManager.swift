import NetworkExtension
import Combine

/// Application-side manager for the LocalDevVPN loopback tunnel.
///
/// Responsibilities:
///   - Load and persist the `NETunnelProviderManager` configuration.
///   - Expose a published `status` property for UI observation.
///   - Provide `startVPN()` and `stopVPN()` methods.
///   - Gate location simulation behind an active VPN connection.
class VPNManager: ObservableObject {

    // MARK: - Published State

    /// The current VPN status (e.g. disconnected, connecting, connected).
    /// UI layers should observe this to reflect tunnel state.
    @Published var status: NEVPNStatus = .invalid

    // MARK: - Private State

    /// The underlying Network Extension manager.  Lazily loaded from preferences.
    private var tunnelManager: NETunnelProviderManager?

    /// Combine cancellables for internal subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Constants

    /// The bundle identifier of the Packet Tunnel Provider extension target.
    /// Must match the extension target’s bundle ID (e.g. `com.yourcompany.locationsimulator.vpn`).
    private let tunnelBundleId = "com.yourcompany.locationsimulator.vpn"

    // MARK: - Init

    init() {
        // Observe global VPN status changes published by the OS.
        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] _ in
                self?.updateStatus()
            }
            .store(in: &cancellables)

        // Prime the local status by loading the saved manager.
        loadSavedManager { [weak self] _ in
            self?.updateStatus()
        }
    }

    // MARK: - Public API

    /// Starts the VPN tunnel if it is not already connected.
    ///
    /// - Parameter completion: Called with an error if the tunnel could not be started.
    func startVPN(completion: ((Error?) -> Void)? = nil) {
        loadSavedManager { [weak self] manager in
            guard let self = self else { return }
            guard let manager = manager else {
                completion?(VPNManagerError.managerNotFound)
                return
            }

            guard let session = manager.connection as? NETunnelProviderSession else {
                completion?(VPNManagerError.managerNotFound)
                return
            }

            do {
                try session.startTunnel()
                DispatchQueue.main.async {
                    self.updateStatus()
                }
                completion?(nil)
            } catch {
                DispatchQueue.main.async {
                    self.updateStatus()
                }
                completion?(error)
            }
        }
    }

    /// Stops the VPN tunnel if it is active.
    ///
    /// - Parameter completion: Called when the stop command has been issued.
    func stopVPN(completion: (() -> Void)? = nil) {
        guard let manager = tunnelManager else {
            completion?()
            return
        }
        guard let session = manager.connection as? NETunnelProviderSession else {
            completion?()
            return
        }
        session.stopTunnel()
        DispatchQueue.main.async {
            self.updateStatus()
        }
        completion?()
    }

    /// Returns `true` if the VPN is currently connected.
    var isConnected: Bool {
        return tunnelManager?.connection.status == .connected
    }

    /// Checks whether the VPN is active and throws a descriptive error if not.
    /// Call this before initiating location simulation.
    ///
    /// - Throws: `VPNManagerError.tunnelNotConnected` when the VPN is down.
    func verifyConnectionForSimulation() throws {
        guard isConnected else {
            throw VPNManagerError.tunnelNotConnected
        }
    }

    // MARK: - Private Helpers

    /// Loads the saved `NETunnelProviderManager` from Network Extension preferences.
    /// If no manager exists, a new one is created and saved automatically.
    ///
    /// - Parameter completion: Returns the loaded/created manager, or `nil` on failure.
    private func loadSavedManager(completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else {
                completion(nil)
                return
            }

            if let error = error {
                print("[VPNManager] Failed to load managers: \(error)")
                completion(nil)
                return
            }

            // Reuse an existing manager whose bundle ID matches our extension.
            if let existing = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
            }) {
                DispatchQueue.main.async {
                    self.tunnelManager = existing
                }
                completion(existing)
                return
            }

            // No saved manager found — create and persist a new one.
            let newManager = NETunnelProviderManager()
            newManager.localizedDescription = "LocationSimulator Loopback VPN"

            let protocolConfig = NETunnelProviderProtocol()
            protocolConfig.providerBundleIdentifier = self.tunnelBundleId
            protocolConfig.serverAddress = "10.7.0.0"
            newManager.protocolConfiguration = protocolConfig

            newManager.isEnabled = true
            newManager.saveToPreferences { [weak self] saveError in
                guard let self = self else {
                    completion(nil)
                    return
                }
                if let saveError = saveError {
                    print("[VPNManager] Failed to save manager: \(saveError)")
                    completion(nil)
                } else {
                    DispatchQueue.main.async {
                        self.tunnelManager = newManager
                    }
                    completion(newManager)
                }
            }
        }
    }

    /// Synchronizes the local `status` property with the tunnel manager’s connection state.
    private func updateStatus() {
        guard let manager = tunnelManager else {
            status = .invalid
            return
        }
        status = manager.connection.status
    }
}

// MARK: - Errors

enum VPNManagerError: Error, LocalizedError {
    case managerNotFound
    case tunnelNotConnected

    var errorDescription: String? {
        switch self {
        case .managerNotFound:
            return "VPN manager could not be loaded from preferences."
        case .tunnelNotConnected:
            return "The VPN tunnel is not connected.  Start the VPN before beginning location simulation."
        }
    }
}
