import Foundation
import Testing
@testable import ALIARCore

@Test func persistentHistorySurvivesReloadAndPreservesBothSources() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = CaptureHistoryStore(fileURL: folder.appendingPathComponent("capture-history.jsonl"))
    #expect(try store.load().isEmpty)
    let first = CaptureArtifact(role: .board, filename: "/some/path/board.jpg",
                                capturedAt: Date(timeIntervalSince1970: 1_000),
                                dimensions: PixelDimensions(width: 1920, height: 1080),
                                byteCount: 123, sha256: String(repeating: "a", count: 64))
    let second = CaptureArtifact(role: .monitor, filename: "/some/path/monitor.jpg",
                                 capturedAt: Date(timeIntervalSince1970: 2_000),
                                 dimensions: PixelDimensions(width: 1280, height: 720),
                                 byteCount: 456, sha256: String(repeating: "b", count: 64))
    let board = CaptureHistoryEntry(artifact: first, origin: .manual)
    let monitor = CaptureHistoryEntry(artifact: second, origin: .pgc, session: "root::worker")
    try store.append(board)
    try store.append(monitor)
    #expect(try store.load() == [monitor, board])
    let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
    #expect(try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
}

@Test func malformedCaptureHistoryIsReportedNotSilentlyDiscarded() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = CaptureHistoryStore(fileURL: folder.appendingPathComponent("capture-history.jsonl"))
    try Data("not-json\n".utf8).write(to: store.fileURL)
    #expect(throws: Error.self) { try store.load() }
}
