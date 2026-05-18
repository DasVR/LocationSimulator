import idevice
import Foundation

enum IDeviceError: Error {
    case ffiError(String)
    case tunnelFailed
    case serverConnectFailed
}

final class IDeviceService: ObservableObject {
    @Published var isConnected = false
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private(set) var remoteServer: OpaquePointer?
    private let port: UInt16 = 49152

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
        guard ffiError == nil else {
            throw IDeviceError.ffiError(String(cString: idevice_error_to_string(ffiError)))
        }

        // 3. Connect remote server
        var server: OpaquePointer?
        let serverErr = remote_server_connect_rsd(tunnelAdapter, tunnelHandshake, &server)
        guard serverErr == nil else {
            // Clean up tunnel resources before throwing
            if let hs = tunnelHandshake { rsd_handshake_free(hs) }
            if let ad = tunnelAdapter { adapter_free(ad) }
            throw IDeviceError.ffiError(String(cString: idevice_error_to_string(serverErr)))
        }

        // 4. Only assign to ivars after all steps succeed atomically.
        self.adapter = tunnelAdapter
        self.handshake = tunnelHandshake
        self.remoteServer = server
        self.isConnected = true
    }

    func disconnect() {
        if let server = remoteServer { remote_server_disconnect(server); remoteServer = nil }
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
                return idevice_error_t(bitPattern: 1) // synthetic error for null base
            }
            return rp_pairing_file_from_bytes(baseAddress, data.count, &handle)
        }
        guard err == nil else { throw IDeviceError.ffiError("Invalid pairing file") }
        guard let handle = handle else {
            throw IDeviceError.ffiError("Pairing file returned null handle")
        }
        return handle
    }
}
