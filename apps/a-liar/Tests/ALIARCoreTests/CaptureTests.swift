import AppKit
import CryptoKit
import Foundation
import Testing
@testable import ALIARCore

@Test func disconnectedDeviceRetainsMapping() throws {
    let inventory = DeviceInventory(deviceIDs: ["board-webcam"])
    var config = AppConfiguration()
    config = try inventory.assigning("board-webcam", to: .board, in: config)
    config = try inventory.assigning("monitor-webcam", to: .monitor, in: config)
    #expect(inventory.status(for: .board, configuration: config) == .available)
    #expect(inventory.status(for: .monitor, configuration: config) == .disconnected)
    #expect(config.mapping(for: .monitor).deviceID == "monitor-webcam")
    let reconnected = DeviceInventory(deviceIDs: ["board-webcam", "monitor-webcam"])
    #expect(reconnected.status(for: .monitor, configuration: config) == .available)
}

@Test func changingAssignedDeviceRevokesAutomation() throws {
    let inventory = DeviceInventory(deviceIDs: ["cam1", "cam2"])
    var config = try inventory.assigning("cam1", to: .board, in: AppConfiguration())
    config.update(.board) { $0.automationAllowed = true }
    config = try inventory.assigning("cam2", to: .board, in: config)
    #expect(config.mapping(for: .board).deviceID == "cam2")
    #expect(config.mapping(for: .board).automationAllowed == false)
    #expect(throws: ConfigurationError.duplicateDevice) {
        try inventory.assigning("cam2", to: .monitor, in: config)
    }
}

@Test func invalidAndOversizedImagesAreRejected() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = CaptureFileStore(directory: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    #expect(throws: CaptureFileError.notJPEG) {
        try store.saveJPEG(Data("not an image".utf8), role: .board)
    }
    #expect(throws: CaptureFileError.invalidImage) {
        try store.saveJPEG(Data([0xff, 0xd8, 0xff, 0xd9]), role: .monitor)
    }
    #expect(throws: CaptureFileError.imageTooLarge) {
        try store.saveJPEG(Data(repeating: 0xff, count: CaptureProtocol.maximumImageBytes + 1), role: .board)
    }
    #expect(!FileManager.default.fileExists(atPath: temp.path))
}

@Test func validJPEGIsSavedWithMetadataPrivatePermissionsAndExpiry() throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]))
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let store = CaptureFileStore(directory: temp)
    let capture = try store.saveJPEG(jpeg, role: .board)
    #expect(capture.dimensions == PixelDimensions(width: 3, height: 2))
    #expect(capture.byteCount == jpeg.count)
    #expect(capture.sha256 == SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined())
    #expect(capture.filename.hasPrefix(temp.path + "/board-"))
    #expect(try Data(contentsOf: URL(fileURLWithPath: capture.filename)) == jpeg)
    let permissions = try FileManager.default.attributesOfItem(atPath: capture.filename)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: capture.filename)
    try store.purgeOlderThan(Date())
    #expect(!FileManager.default.fileExists(atPath: capture.filename))
}
