import Foundation
import Testing
@testable import ALIARCore

@Test func configurationDefaultsDenyAll() throws {
    let configuration = AppConfiguration()
    try configuration.validate()
    for role in CameraRole.allCases {
        #expect(configuration.mapping(for: role).deviceID == nil)
        #expect(configuration.mapping(for: role).automationAllowed == false)
    }
}

@Test func duplicateCameraCannotBeSaved() throws {
    var configuration = AppConfiguration()
    configuration.update(.board) { $0.deviceID = "same" }
    configuration.update(.monitor) { $0.deviceID = "same" }
    #expect(throws: ConfigurationError.duplicateDevice) { try configuration.validate() }
}

@Test func configurationRoundTrip() throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("settings.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = ConfigurationStore(fileURL: file)
    var configuration = AppConfiguration()
    configuration.update(.board) {
        $0.deviceID = "camera-unique-123"
        $0.resolution = PixelDimensions(width: 1920, height: 1080)
        $0.automationAllowed = true
    }
    try store.save(configuration)
    #expect(try store.load() == configuration)
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

@Test func explicitUnattendedGrantExpiresAndIsBounded() {
    var configuration = AppConfiguration()
    configuration.update(.board) {
        $0.deviceID = "webcam-1"
        $0.automationAllowed = true
    }
    var policy = AutomationPolicy()
    let now = Date(timeIntervalSince1970: 1_000_000)
    let owner = "83a276118d7867c4"
    let other = "another-pgc-session"
    #expect(policy.authorize(.board, session: owner, configuration: configuration, now: now) == .sessionNotGranted)
    #expect(policy.authorize(.monitor, session: owner, configuration: configuration, now: now) == .cameraNotMapped)
    policy.grant(to: owner, for: 12 * 60 * 60, now: now)
    #expect(policy.unattendedUntil == now.addingTimeInterval(6 * 60 * 60))
    #expect(policy.grantedSession == owner)
    #expect(policy.authorize(.board, session: owner, configuration: configuration, now: now) == nil)
    #expect(policy.authorize(.board, session: other, configuration: configuration, now: now) == .sessionNotGranted)
    #expect(policy.authorize(.board, session: owner, configuration: configuration, now: now.addingTimeInterval(6 * 60 * 60)) == .unattendedAccessInactive)
    policy.revoke()
    #expect(policy.authorize(.board, session: owner, configuration: configuration, now: now) == .sessionNotGranted)
}

@Test func sessionIdentifiersHaveStrictBounds() {
    #expect(PGCSessionID.isValid("abc123"))
    #expect(PGCSessionID.isValid("abc123::worker-name"))
    for invalid in ["", "../escape", " bad", "a/b", "a\nB", String(repeating: "x", count: 129)] {
        #expect(!PGCSessionID.isValid(invalid))
    }
}

@Test func protocolIsStrictAndBounded() throws {
    let request = CaptureRequest(camera: .monitor, session: "83a276118d7867c4::worker", requestID: "test-001")
    let line = try CaptureProtocol.encodeRequest(request)
    #expect(try CaptureProtocol.decodeRequest(Data(line.dropLast())) == request)
    #expect(throws: ProtocolError.invalidFields) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":2,"command":"capture","camera":"board","session":"root","path":"/tmp/file"}"#.utf8))
    }
    #expect(throws: ProtocolError.invalidFields) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":2,"command":"capture","camera":"not-a-camera","session":"root"}"#.utf8))
    }
    #expect(throws: ProtocolError.invalidFields) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":2,"command":"capture","camera":"board","session":"../other"}"#.utf8))
    }
    #expect(throws: ProtocolError.invalidFields) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":2,"command":"capture","camera":"board"}"#.utf8))
    }
    #expect(throws: ProtocolError.unsupportedVersion) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":1,"command":"capture","camera":"board","session":"root"}"#.utf8))
    }
    #expect(throws: ProtocolError.unsupportedCommand) {
        try CaptureProtocol.decodeRequest(Data(#"{"version":2,"command":"delete","camera":"board","session":"root"}"#.utf8))
    }
    #expect(throws: ProtocolError.oversized) {
        try CaptureProtocol.decodeRequest(Data(repeating: 65, count: CaptureProtocol.maximumRequestBytes + 1))
    }
}

@Test func outputMetadataHasNoImageBytes() throws {
    let response = CaptureResponse.success(camera: .board, filename: "/tmp/safe-uuid.jpg", capturedAt: Date(timeIntervalSince1970: 0), dimensions: PixelDimensions(width: 1280, height: 720), byteCount: 12_345, sha256: String(repeating: "a", count: 64))
    let data = try CaptureProtocol.encodeResponse(response)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["filename"] as? String == "/tmp/safe-uuid.jpg")
    #expect(object["byte_count"] as? Int == 12_345)
    #expect(object["image"] == nil)
}
