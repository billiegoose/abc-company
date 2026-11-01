import Foundation

public enum CameraRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case board
    case monitor

    public var id: String { rawValue }
    public var title: String { self == .board ? "Basys 3 board" : "VGA monitor" }
}

public struct PixelDimensions: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var id: String { "\(width)x\(height)" }
    public var label: String { "\(width) × \(height)" }
    public var isReasonable: Bool {
        width > 0 && height > 0 && width <= 8192 && height <= 8192 &&
        Int64(width) * Int64(height) <= 33_554_432
    }
}

public struct CameraMapping: Codable, Equatable, Sendable {
    public var deviceID: String?
    public var resolution: PixelDimensions?
    public var automationAllowed: Bool

    public init(deviceID: String? = nil, resolution: PixelDimensions? = nil, automationAllowed: Bool = false) {
        self.deviceID = deviceID
        self.resolution = resolution
        self.automationAllowed = automationAllowed
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var cameras: [CameraRole: CameraMapping] = [
        .board: CameraMapping(),
        .monitor: CameraMapping(),
    ]

    public init() {}

    public func mapping(for role: CameraRole) -> CameraMapping {
        cameras[role] ?? CameraMapping()
    }

    public mutating func update(_ role: CameraRole, _ change: (inout CameraMapping) -> Void) {
        var mapping = self.mapping(for: role)
        change(&mapping)
        cameras[role] = mapping
    }

    public func validate() throws {
        guard version == Self.currentVersion else { throw ConfigurationError.unsupportedVersion }
        let ids = CameraRole.allCases.compactMap { mapping(for: $0).deviceID }
        guard Set(ids).count == ids.count else { throw ConfigurationError.duplicateDevice }
        for role in CameraRole.allCases {
            let entry = mapping(for: role)
            if let id = entry.deviceID, id.isEmpty || id.utf8.count > 1024 {
                throw ConfigurationError.invalidDeviceID
            }
            if let dimensions = entry.resolution, !dimensions.isReasonable {
                throw ConfigurationError.invalidDimensions
            }
        }
    }
}

public enum ConfigurationError: Error, Equatable, LocalizedError {
    case unsupportedVersion
    case duplicateDevice
    case invalidDeviceID
    case invalidDimensions

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "Unsupported configuration version"
        case .duplicateDevice: "One physical camera cannot be assigned to both instruments"
        case .invalidDeviceID: "Invalid camera device identifier"
        case .invalidDimensions: "Invalid capture resolution"
        }
    }
}

public struct ConfigurationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultStore() throws -> ConfigurationStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return ConfigurationStore(fileURL: base
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("settings.json"))
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppConfiguration() }
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fileURL))
        try configuration.validate()
        return configuration
    }

    public func save(_ configuration: AppConfiguration) throws {
        try configuration.validate()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
