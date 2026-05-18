import NetworkExtension

/// Packet tunnel provider that creates a loopback interface for local development.
/// Traffic destined to `10.7.0.1` is rewritten so it routes back to the device itself,
/// allowing local servers to be reached via a stable fake IP.
class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Constants

    /// The tunnel interface IP assigned to the device.
    private let tunnelDeviceIp = "10.7.0.0"

    /// The "fake" destination IP that we rewrite back to the device.
    private let tunnelFakeIp = "10.7.0.1"

    /// Subnet mask for the loopback tunnel network.
    private let tunnelSubnetMask = "255.255.255.0"

    // MARK: - Tunnel Lifecycle

    /// Called by the system when the VPN tunnel is requested to start.
    /// Configures the tunnel network settings and begins the packet read loop.
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 1. Create tunnel settings with the device IP as the remote address.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelDeviceIp)

        // 2. Configure IPv4 settings: assign the tunnel device IP and subnet mask.
        let ipv4 = NEIPv4Settings(addresses: [tunnelDeviceIp], subnetMasks: [tunnelSubnetMask])

        // 3. Only route the tunnel subnet (10.7.0.0/24) into the tunnel.
        //    Using NEIPv4Route(destinationAddress:subnetMask:) ensures that only
        //    traffic destined for the loopback subnet is captured.
        //    ⚠️ Anti-pattern guard: do NOT add .default() to includedRoutes.
        //    Doing so would route ALL device traffic through the tunnel and break
        //    internet connectivity.
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: tunnelDeviceIp, subnetMask: tunnelSubnetMask)]

        // 4. Exclude the default route so regular internet traffic bypasses the tunnel.
        ipv4.excludedRoutes = [.default()]

        settings.ipv4Settings = ipv4

        // 5. Apply settings and start reading packets.
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else {
                completionHandler(error)
                return
            }
            self.setPackets()
            completionHandler(error)
        }
    }

    // MARK: - Packet Rewriting

    /// Begins an indefinite read-modify-write loop on the packet flow.
    ///
    /// For every IPv4 packet received:
    ///   - Parse the source and destination IP addresses from the IPv4 header.
    ///   - If the source IP matches `tunnelDeviceIp`, rewrite it to `tunnelFakeIp`
    ///     so the packet appears to originate from the fake address.
    ///   - If the destination IP matches `tunnelFakeIp`, rewrite it to `tunnelDeviceIp`
    ///     so the packet is delivered back to the device itself.
    ///   - Write the modified packet(s) back out through the tunnel.
    ///
    /// IP header layout (first 20 bytes):
    ///   Bytes 0-3:   Version/IHL, TOS, Total Length
    ///   Bytes 4-7:   Identification, Flags, Fragment Offset
    ///   Bytes 8-11:  TTL, Protocol, Header Checksum
    ///   Bytes 12-15: Source IP Address      → treated as UInt32 at offset 3
    ///   Bytes 16-19: Destination IP Address → treated as UInt32 at offset 4
    ///
    /// We use `withUnsafeMutableBytes` for zero-copy access to the packet data,
    /// and `assumingMemoryBound(to: UInt32.self)` to reinterpret the header as
    /// an array of 32-bit words.  All accesses are bounds-checked before entry.
    private func setPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            // Convert string IPs to UInt32 for fast header comparison.
            let deviceIp = self.ipv4ToUInt32(self.tunnelDeviceIp)
            let fakeIp   = self.ipv4ToUInt32(self.tunnelFakeIp)

            // Work on a mutable copy of the packet array.
            var modified = packets

            for i in modified.indices where protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                modified[i].withUnsafeMutableBytes { bytes in
                    // Ensure we have a valid base address before binding memory.
                    guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }

                    // ptr[3] corresponds to bytes 12-15 (source IP) in big-endian layout.
                    let src = UInt32(bigEndian: ptr[3])
                    // ptr[4] corresponds to bytes 16-19 (destination IP) in big-endian layout.
                    let dst = UInt32(bigEndian: ptr[4])

                    // Rewrite outbound packets so they appear to come from the fake IP.
                    if src == deviceIp {
                        ptr[3] = fakeIp.bigEndian
                    }

                    // Rewrite inbound packets destined for the fake IP back to the device IP.
                    if dst == fakeIp {
                        ptr[4] = deviceIp.bigEndian
                    }
                }

                // Recompute the IPv4 header checksum since we modified source/dest IPs.
                self.recomputeIPv4Checksum(&modified[i])
            }

            // Push modified packets back into the tunnel and recurse for the next batch.
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            self.setPackets()
        }
    }

    /// Converts a dot-decimal IPv4 string (e.g. "10.7.0.1") into a big-endian `UInt32`.
    private func ipv4ToUInt32(_ ip: String) -> UInt32 {
        guard ip.split(separator: ".").count == 4 else { return 0 }
        return ip.split(separator: ".").reduce(0) {
            guard let octet = UInt32($1), octet <= 255 else { return $0 }
            return ($0 << 8) + octet
        }
    }

    // MARK: - IPv4 Header Checksum

    /// Recomputes the IPv4 header checksum after modifying header fields.
    ///
    /// The checksum covers the first 20 bytes of the IPv4 header. After any
    /// header field (such as source or destination IP) is changed, the checksum
    /// at bytes 10–11 must be recalculated or the packet will be discarded.
    ///
    /// Algorithm:
    /// 1. Zero out the existing checksum field.
    /// 2. Sum every 16-bit word in the header.
    /// 3. Add any carry back into the sum.
    /// 4. Take the one's complement of the result.
    /// 5. Store in big-endian.
    private func recomputeIPv4Checksum(_ data: inout Data) {
        guard data.count >= 20 else { return }

        data.withUnsafeMutableBytes { bytes in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt16.self) else { return }

            ptr[5] = 0

            var sum: UInt32 = 0
            for i in 0..<10 {
                sum += UInt32(UInt16(bigEndian: ptr[i]))
            }

            while (sum >> 16) != 0 {
                sum = (sum & 0xFFFF) + (sum >> 16)
            }

            let checksum = UInt16(~sum).bigEndian
            ptr[5] = checksum
        }
    }

    // MARK: - Stop Tunnel

    /// Called by the system when the VPN tunnel is requested to stop.
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Clean-up is handled automatically by the system tearing down the packet flow.
        completionHandler()
    }
}
