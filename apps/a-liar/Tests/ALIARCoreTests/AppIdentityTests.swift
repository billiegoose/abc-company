import Foundation
import Testing
@testable import ALIARCore

@Test func appIdentityUsesApplePieNameAndPaths() {
    #expect(AppIdentity.name == "A.P.P.L.E.P.I.E.")
    #expect(AppIdentity.bundleIdentifier == "com.ananabanana.APPLEPIE")
    #expect(AppIdentity.supportDirectoryName == "APPLEPIE")
}

@Test func migrationPreservesLegacyFilesAndDoesNotCopySocket() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("applepie-migration-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let legacy = base.appendingPathComponent("A-LIAR", isDirectory: true)
    let current = base.appendingPathComponent("APPLEPIE", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let legacySettings = legacy.appendingPathComponent("settings.json")
    let legacyHistory = legacy.appendingPathComponent("capture-history.jsonl")
    try Data("old-settings".utf8).write(to: legacySettings)
    try Data("old-history\n".utf8).write(to: legacyHistory)
    try Data("not-a-socket".utf8).write(to: legacy.appendingPathComponent("capture.sock"))

    try AppDataMigration.migrateIfNeeded(applicationSupportDirectory: base)
    #expect(try Data(contentsOf: current.appendingPathComponent("settings.json")) == Data("old-settings".utf8))
    #expect(try Data(contentsOf: current.appendingPathComponent("capture-history.jsonl")) == Data("old-history\n".utf8))
    #expect(!FileManager.default.fileExists(atPath: current.appendingPathComponent("capture.sock").path))
    #expect(try Data(contentsOf: legacySettings) == Data("old-settings".utf8))
    let directoryMode = try FileManager.default.attributesOfItem(atPath: current.path)[.posixPermissions] as? Int
    let fileMode = try FileManager.default.attributesOfItem(atPath: current.appendingPathComponent("settings.json").path)[.posixPermissions] as? Int
    #expect(directoryMode == 0o700)
    #expect(fileMode == 0o600)

    try Data("new-settings".utf8).write(to: current.appendingPathComponent("settings.json"))
    try AppDataMigration.migrateIfNeeded(applicationSupportDirectory: base)
    #expect(try Data(contentsOf: current.appendingPathComponent("settings.json")) == Data("new-settings".utf8))
}
