import IDevice
import Foundation

enum IDeviceError: Error {
    case ffiError(String)
    case tunnelFailed
    case serverConnectFailed
}

final class IDeviceService: ObservableObject {
    @Published var isConnected = false
    @Published var lastError: String?
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private(set) var remoteServer: OpaquePointer?
    private let port: UInt16 = 49152
    private var reconnectTask: Task<Void, Never>?

    func connect(hostname: String = "10.7.0.1") throws {
        // If already connected, disconnect first to prevent handle leaks.
        if isConnected { disconnect() }

        // 1. Load pairing file
        let pairingFile = try loadPairingFile()
        defer { rp_pairing_file_free(pairingFile) }

        // 2. Create RPPairing tunnel
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(hostname)

        var tunnelAdapter: OpaquePointer?
        var tunnelHandshake: OpaquePointer?

        let ffiError = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: idevice_sockaddr.self, capacity: 1) { boundAddr in
                tunnel_create_rppairing(
                    boundAddr,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    hostname,
                    pairingFile,
                    nil, nil,
                    &tunnelAdapter,
                    &tunnelHandshake
                )
            }
        }
        if let err = ffiError {
            let msg = String(cString: err.pointee.message)
            throw IDeviceError.ffiError(msg)
        }

        // 3. Connect remote server
        var server: OpaquePointer?
        let serverErr = remote_server_connect_rsd(tunnelAdapter, tunnelHandshake, &server)
        if let err = serverErr {
            if let hs = tunnelHandshake { rsd_handshake_free(hs) }
            if let ad = tunnelAdapter { adapter_free(ad) }
            let msg = String(cString: err.pointee.message)
            throw IDeviceError.ffiError(msg)
        }

        // 4. Only assign to ivars after all steps succeed atomically.
        self.adapter = tunnelAdapter
        self.handshake = tunnelHandshake
        self.remoteServer = server
        self.isConnected = true
        self.lastError = nil
    }

    /// Attempts to reconnect up to `maxAttempts` times with exponential backoff.
    func reconnect(hostname: String = "10.7.0.1", maxAttempts: Int = 3) {
        reconnectTask?.cancel()
        reconnectTask = Task {
            for attempt in 1...maxAttempts {
                guard !Task.isCancelled else { return }
                do {
                    try connect(hostname: hostname)
                    return
                } catch {
                    let delay = min(Double(attempt) * 2.0, 10.0)
                    self.lastError = error.localizedDescription
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        if let server = remoteServer { remote_server_free(server); remoteServer = nil }
        if let hs = handshake { rsd_handshake_free(hs); handshake = nil }
        if let ad = adapter { adapter_free(ad); adapter = nil }
        isConnected = false
    }

    deinit { disconnect() }

    private func loadPairingFile() throws -> OpaquePointer {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rp_pairing_file.plist")
        let data = try Data(contentsOf: url)
        var handle: OpaquePointer?
        let err = data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return UnsafePointer<IdeviceFfiError>(bitPattern: 1)
            }
            return rp_pairing_file_from_bytes(baseAddress, data.count, &handle)
        }
        if let err = err {
            let msg = String(cString: err.pointee.message)
            throw IDeviceError.ffiError(msg)
        }
        guard let handle = handle else {
            throw IDeviceError.ffiError("Pairing file returned null handle")
        }
        return handle
    }
}
