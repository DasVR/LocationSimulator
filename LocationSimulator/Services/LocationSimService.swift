import idevice
import Foundation

final class LocationSimService: ObservableObject {
    private var simHandle: OpaquePointer?
    private let deviceService: IDeviceService

    init(deviceService: IDeviceService) {
        self.deviceService = deviceService
    }

    func startSimulation() throws {
        guard simHandle == nil else { return }
        guard let server = deviceService.remoteServer else {
            throw IDeviceError.serverConnectFailed
        }
        var handle: OpaquePointer?
        let err = location_simulation_new(server, &handle)
        guard err == nil else {
            throw IDeviceError.ffiError("Failed to create location simulation handle")
        }
        self.simHandle = handle
    }

    func setLocation(latitude: Double, longitude: Double) throws {
        guard let handle = simHandle else {
            throw IDeviceError.ffiError("Simulation not started")
        }
        let err = location_simulation_set(handle, latitude, longitude)
        guard err == nil else {
            throw IDeviceError.ffiError("Failed to set location")
        }
    }

    func clearLocation() throws {
        guard let handle = simHandle else { return }
        let err = location_simulation_clear(handle)
        guard err == nil else {
            throw IDeviceError.ffiError("Failed to clear location")
        }
    }

    func stopSimulation() {
        if let handle = simHandle {
            location_simulation_free(handle)
            simHandle = nil
        }
    }
}
