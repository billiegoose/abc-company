import Foundation

public enum DeviceStatus: Equatable, Sendable {
    case unassigned
    case disconnected
    case available
}

public struct DeviceInventory: Sendable {
    public var deviceIDs: Set<String>

    public init(deviceIDs: Set<String>) { self.deviceIDs = deviceIDs }

    public func status(for role: CameraRole, configuration: AppConfiguration) -> DeviceStatus {
        guard let id = configuration.mapping(for: role).deviceID else { return .unassigned }
        return deviceIDs.contains(id) ? .available : .disconnected
    }

    public func assigning(_ deviceID: String?, to role: CameraRole, in config: AppConfiguration) throws -> AppConfiguration {
        var updated = config
        updated.update(role) { mapping in
            if mapping.deviceID != deviceID {
                mapping.deviceID = deviceID
                mapping.resolution = nil
                mapping.automationAllowed = false // A new device must be explicitly approved again.
            }
        }
        try updated.validate()
        return updated
    }
}
