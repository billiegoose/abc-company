import CryptoKit
import Foundation
import ImageIO

public enum CaptureFileError: Error, Equatable {
    case notJPEG
    case invalidImage
    case imageTooLarge
}

public struct CaptureArtifact: Sendable {
    public let role: CameraRole
    public let filename: String
    public let capturedAt: Date
    public let dimensions: PixelDimensions
    public let byteCount: Int
    public let sha256: String

    public var response: CaptureResponse {
        .success(camera: role, filename: filename, capturedAt: capturedAt,
                 dimensions: dimensions, byteCount: byteCount, sha256: sha256)
    }
}

public struct CaptureFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func defaultStore() throws -> CaptureFileStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return CaptureFileStore(directory: applicationSupport
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("captures", isDirectory: true))
    }

    @discardableResult
    public func saveJPEG(_ jpeg: Data, role: CameraRole, date: Date = Date()) throws -> CaptureArtifact {
        guard jpeg.count <= CaptureProtocol.maximumImageBytes else { throw CaptureFileError.imageTooLarge }
        guard jpeg.count >= 4, jpeg[0] == 0xFF, jpeg[1] == 0xD8 else { throw CaptureFileError.notJPEG }
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CaptureFileError.invalidImage
        }
        let dimensions = PixelDimensions(width: width, height: height)
        guard dimensions.isReasonable else { throw CaptureFileError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let name = "\(role.rawValue)-\(UUID().uuidString).jpg"
        let file = directory.appendingPathComponent(name, isDirectory: false)
        try jpeg.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let hash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        return CaptureArtifact(role: role, filename: file.path, capturedAt: date,
                               dimensions: dimensions, byteCount: jpeg.count, sha256: hash)
    }

    public func purgeOlderThan(_ cutoff: Date) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, file.pathExtension == "jpg",
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}
