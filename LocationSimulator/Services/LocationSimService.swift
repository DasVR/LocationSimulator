import IDevice
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
        if let err = err {
            throw IDeviceError.ffiError(String(cString: err.pointee.message))
        }
        self.simHandle = handle
    }

    func setLocation(latitude: Double, longitude: Double) throws {
        guard let handle = simHandle else {
            throw IDeviceError.ffiError("Simulation not started")
        }
        let err = location_simulation_set(handle, latitude, longitude)
        if let err = err {
            throw IDeviceError.ffiError(String(cString: err.pointee.message))
        }
    }

    func clearLocation() throws {
        guard let handle = simHandle else { return }
        let err = location_simulation_clear(handle)
        if let err = err {
            throw IDeviceError.ffiError(String(cString: err.pointee.message))
        }
    }

    func stopSimulation() {
        if let handle = simHandle {
            location_simulation_free(handle)
            simHandle = nil
        }
    }
}
