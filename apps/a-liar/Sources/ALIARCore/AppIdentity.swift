import Foundation

public enum AppIdentity {
    public static let name = "A.P.P.L.E.P.I.E."
    public static let fullName = "ANANA Permissions Protected Lab Equipment Proxy for Internet Entities"
    public static let bundleIdentifier = "com.ananabanana.APPLEPIE"
    public static let supportDirectoryName = "APPLEPIE"
    public static let legacySupportDirectoryName = "A-LIAR"
}

/// Copies only persistent operator data when changing from the old app identity.
/// Original files remain in place; sockets, lock files and JPEGs are not migrated.
public enum AppDataMigration {
    public static func migrateIfNeeded(applicationSupportDirectory: URL? = nil) throws {
        let manager = FileManager.default
        let base: URL
        if let applicationSupportDirectory {
            base = applicationSupportDirectory
        } else {
            base = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
        }
        let legacy = base.appendingPathComponent(AppIdentity.legacySupportDirectoryName, isDirectory: true)
        let current = base.appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: legacy.path, isDirectory: &isDirectory) else { return }
        let legacyValues = try legacy.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard isDirectory.boolValue, legacyValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission)
        }

        var pending: [(source: URL, destination: URL)] = []
        for name in ["settings.json", "capture-history.jsonl"] {
            let source = legacy.appendingPathComponent(name)
            let destination = current.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path),
                  !manager.fileExists(atPath: destination.path) else { continue }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadNoPermission)
            }
            pending.append((source, destination))
        }
        guard !pending.isEmpty else { return }
        try manager.createDirectory(at: current, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: current.path)
        for item in pending {
            try manager.copyItem(at: item.source, to: item.destination)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.destination.path)
        }
    }
}
