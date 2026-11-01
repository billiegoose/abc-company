import Foundation

public enum CaptureOrigin: String, Codable, Sendable {
    case manual
    case pgc
}

public struct CaptureHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: CameraRole
    public let origin: CaptureOrigin
    public let session: String?
    public let capturedAt: Date
    public let filename: String
    public let dimensions: PixelDimensions
    public let byteCount: Int
    public let sha256: String

    public init(artifact: CaptureArtifact, origin: CaptureOrigin, session: String? = nil) {
        id = UUID()
        role = artifact.role
        self.origin = origin
        self.session = session
        capturedAt = artifact.capturedAt
        filename = artifact.filename
        dimensions = artifact.dimensions
        byteCount = artifact.byteCount
        sha256 = artifact.sha256
    }
}

/// Append-only local metadata. JPEGs may expire; their history records do not.
public struct CaptureHistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultStore() throws -> Self {
        let parent = try ConfigurationStore.defaultStore().fileURL.deletingLastPathComponent()
        return Self(fileURL: parent.appendingPathComponent("capture-history.jsonl"))
    }

    public func load() throws -> [CaptureHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let bytes = try Data(contentsOf: fileURL)
        let lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.reversed().map { try decoder.decode(CaptureHistoryEntry.self, from: Data($0)) }
    }

    public func append(_ entry: CaptureHistoryEntry) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                                attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
