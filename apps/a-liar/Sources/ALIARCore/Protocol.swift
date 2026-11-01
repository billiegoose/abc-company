import Foundation

public struct CaptureRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let command: String
    public let camera: CameraRole
    public let session: String
    public let requestID: String?

    public init(version: Int = 2, command: String = "capture", camera: CameraRole, session: String, requestID: String? = nil) {
        self.version = version
        self.command = command
        self.camera = camera
        self.session = session
        self.requestID = requestID
    }
}

public struct CaptureResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let ok: Bool
    public let camera: CameraRole?
    public let filename: String?
    public let capturedAt: Date?
    public let width: Int?
    public let height: Int?
    public let byteCount: Int?
    public let sha256: String?
    public let code: String?
    public let error: String?

    public static func success(camera: CameraRole, filename: String, capturedAt: Date, dimensions: PixelDimensions, byteCount: Int, sha256: String) -> Self {
        Self(version: 2, ok: true, camera: camera, filename: filename, capturedAt: capturedAt,
             width: dimensions.width, height: dimensions.height, byteCount: byteCount, sha256: sha256,
             code: nil, error: nil)
    }

    public static func failure(_ code: String, _ message: String, camera: CameraRole? = nil) -> Self {
        Self(version: 2, ok: false, camera: camera, filename: nil, capturedAt: nil,
             width: nil, height: nil, byteCount: nil, sha256: nil, code: code, error: message)
    }
}

public enum ProtocolError: Error, Equatable {
    case oversized
    case invalidJSON
    case invalidFields
    case unsupportedVersion
    case unsupportedCommand
}

public enum CaptureProtocol {
    public static let version = 2
    public static let maximumRequestBytes = 4096
    public static let maximumImageBytes = 16 * 1024 * 1024
    public static let captureTimeout: TimeInterval = 20

    public static func decodeRequest(_ bytes: Data) throws -> CaptureRequest {
        guard bytes.count <= maximumRequestBytes else { throw ProtocolError.oversized }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw ProtocolError.invalidJSON
        }
        let permitted: Set<String> = ["version", "command", "camera", "session", "request_id"]
        guard Set(object.keys).isSubset(of: permitted),
              let version = object["version"] as? Int,
              let command = object["command"] as? String,
              let cameraString = object["camera"] as? String,
              let camera = CameraRole(rawValue: cameraString),
              let session = object["session"] as? String,
              PGCSessionID.isValid(session),
              (object["request_id"] == nil || object["request_id"] is String) else {
            throw ProtocolError.invalidFields
        }
        guard version == Self.version else { throw ProtocolError.unsupportedVersion }
        guard command == "capture" else { throw ProtocolError.unsupportedCommand }
        let requestID = object["request_id"] as? String
        if let requestID {
            let valid = requestID.utf8.count > 0 && requestID.utf8.count <= 64 &&
                requestID.utf8.allSatisfy { byte in
                    (48...57).contains(byte) || (65...90).contains(byte) ||
                    (97...122).contains(byte) || byte == 45 || byte == 46 || byte == 95
                }
            guard valid else { throw ProtocolError.invalidFields }
        }
        return CaptureRequest(version: version, command: command, camera: camera, session: session, requestID: requestID)
    }

    public static func encodeRequest(_ request: CaptureRequest) throws -> Data {
        var object: [String: Any] = ["version": request.version, "command": request.command, "camera": request.camera.rawValue, "session": request.session]
        if let requestID = request.requestID { object["request_id"] = requestID }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    public static func encodeResponse(_ response: CaptureResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(response)
        data.append(0x0A)
        return data
    }
}
