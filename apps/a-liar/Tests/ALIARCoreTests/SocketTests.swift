import Darwin
import Foundation
import Testing
@testable import ALIARCore

@Test func localSocketHandlesMockCaptureAndRejectsInvalidRequests() async throws {
    let temporary = URL(fileURLWithPath: "/tmp/aliar-\(UUID().uuidString.prefix(8))", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let socketURL = temporary.appendingPathComponent("lab.sock")
    let server = LocalCaptureSocket(socketURL: socketURL) { request in
        .failure("test_capture_denied", "Mock camera deliberately denied", camera: request.camera)
    }
    try server.start()
    defer { server.stop() }
    let secondServer = LocalCaptureSocket(socketURL: socketURL) { _ in .failure("unreachable", "Blocked") }
    #expect(throws: LocalSocketError.self) { try secondServer.start() }
    let overlong = try LocalCaptureClient.sendRaw(
        Data(repeating: 65, count: CaptureProtocol.maximumRequestBytes + 2) + Data([10]),
        socketURL: socketURL
    )
    #expect(overlong.code == "request_too_large")
    let response = try LocalCaptureClient.request(.init(camera: .board, session: "root-session"), socketURL: socketURL)
    #expect(response.ok == false)
    #expect(response.code == "test_capture_denied")
    #expect(response.camera == .board)
    let invalid = try LocalCaptureClient.sendRaw(
        Data(#"{"version":2,"camera":"board","command":"delete","session":"root-session"}"#.utf8) + Data([10]),
        socketURL: socketURL
    )
    #expect(invalid.code == "unsupported_command")
    let traversal = try LocalCaptureClient.sendRaw(
        Data(#"{"version":2,"camera":"monitor","command":"capture","session":"root-session","path":"../../secret"}"#.utf8) + Data([10]),
        socketURL: socketURL
    )
    #expect(traversal.code == "invalid_request")
    var attributes = stat()
    #expect(lstat(socketURL.path, &attributes) == 0)
    #expect(attributes.st_mode & mode_t(0o777) == mode_t(0o600))
}

@Test func localSocketDoesNotOverwriteUnrelatedFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aliar-file-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("lab.sock")
    try Data("important".utf8).write(to: path)
    let server = LocalCaptureSocket(socketURL: path) { _ in .failure("denied", "Denied") }
    #expect(throws: LocalSocketError.self) { try server.start() }
    #expect(try String(contentsOf: path, encoding: .utf8) == "important")
}
