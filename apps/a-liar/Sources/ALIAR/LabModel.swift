import AppKit
import AVFoundation
import Foundation
import ALIARCore

@MainActor
final class LabModel: ObservableObject {
    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var cameraAuthorization: AVAuthorizationStatus
    @Published private(set) var notice = "Camera access is idle"
    @Published private(set) var lastCaptures: [CameraRole: CaptureArtifact] = [:]
    @Published private(set) var captureHistory: [CaptureHistoryEntry] = []
    @Published private(set) var historyWarning: String?
    @Published private(set) var activeCapture: CameraRole?
    @Published private(set) var unattendedUntil: Date?
    @Published private(set) var grantedSession: String?
    @Published private(set) var knownSessions: [String] = []
    @Published var selectedSession: String?
    @Published private(set) var socketStatus = "Socket server not started"

    let boardChannel = CameraChannel()
    let monitorChannel = CameraChannel()

    private let settingsStore: ConfigurationStore?
    private let fileStore: CaptureFileStore?
    private let historyStore: CaptureHistoryStore?
    private var policy = AutomationPolicy()
    private var socket: LocalCaptureSocket?
    private var automatedCaptureRole: CameraRole?
    private var deviceObservers: [NSObjectProtocol] = []

    init() {
        var migrationFailure: String?
        do { try AppDataMigration.migrateIfNeeded() }
        catch { migrationFailure = error.localizedDescription }
        settingsStore = try? ConfigurationStore.defaultStore()
        fileStore = try? CaptureFileStore.defaultStore()
        historyStore = try? CaptureHistoryStore.defaultStore()
        do {
            configuration = try settingsStore?.load() ?? AppConfiguration()
        } catch {
            configuration = AppConfiguration() // Corrupt settings must never grant automation.
            notice = "Could not load settings: \(error.localizedDescription). Automation is disabled."
        }
        if let historyStore {
            do { captureHistory = try historyStore.load() }
            catch { historyWarning = "Could not read existing capture history: \(error.localizedDescription)" }
        } else {
            historyWarning = "Capture history storage is unavailable"
        }
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        refreshDevices()
        startSocket()
        if let migrationFailure {
            notice = "Previous camera settings or history could not be migrated: \(migrationFailure)"
        }
        for notification in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(NotificationCenter.default.addObserver(
                forName: notification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshDevices() }
            })
        }
    }

    func channel(for role: CameraRole) -> CameraChannel {
        role == .board ? boardChannel : monitorChannel
    }

    func refreshDevices() {
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        devices = CameraChannel.connectedDevices()
        let inventory = DeviceInventory(deviceIDs: Set(devices.map(\.uniqueID)))
        for role in CameraRole.allCases {
            if inventory.status(for: role, configuration: configuration) == .disconnected {
                channel(for: role).stop()
            }
        }
    }

    func isConnected(_ role: CameraRole) -> Bool {
        DeviceInventory(deviceIDs: Set(devices.map(\.uniqueID)))
            .status(for: role, configuration: configuration) == .available
    }

    func resolutions(for role: CameraRole) -> [PixelDimensions] {
        guard let id = configuration.mapping(for: role).deviceID,
              let device = devices.first(where: { $0.uniqueID == id }) else { return [] }
        return CameraChannel.resolutions(for: device)
    }

    func askForCameraPermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
            notice = granted ? "macOS Camera access granted to A.P.P.L.E.P.I.E." : "Camera access denied. See System Settings → Privacy & Security → Camera."
            refreshDevices()
        }
    }

    func assignDevice(_ deviceID: String?, to role: CameraRole) {
        do {
            let inventory = DeviceInventory(deviceIDs: Set(devices.map(\.uniqueID)))
            let updated = try inventory.assigning(deviceID, to: role, in: configuration)
            guard let settingsStore else { throw CameraCaptureError(message: "Settings storage is unavailable") }
            try settingsStore.save(updated)
            channel(for: role).stop()
            configuration = updated
            notice = "Camera assignment saved for \(role.title). Automation approval was reset if the camera changed."
        } catch {
            notice = "Cannot assign camera: \(error.localizedDescription)"
        }
    }

    func chooseResolution(_ resolution: PixelDimensions?, for role: CameraRole) {
        var updated = configuration
        updated.update(role) { $0.resolution = resolution }
        save(updated)
        channel(for: role).stop()
    }

    func allowAutomation(_ allowed: Bool, for role: CameraRole) {
        if !allowed && automatedCaptureRole == role { channel(for: role).stop() }
        var updated = configuration
        updated.update(role) { $0.automationAllowed = allowed && $0.deviceID != nil }
        save(updated)
    }

    private func save(_ updated: AppConfiguration) {
        do {
            guard let settingsStore else { throw CameraCaptureError(message: "Settings storage is unavailable") }
            try settingsStore.save(updated)
            configuration = updated
        } catch {
            notice = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    func startPreview(_ role: CameraRole) {
        guard let id = configuration.mapping(for: role).deviceID else {
            notice = "Assign a camera first"
            return
        }
        do {
            try channel(for: role).startPreview(
                deviceID: id, resolution: configuration.mapping(for: role).resolution
            )
            notice = "Live preview started for \(role.title) (local display only)"
        } catch {
            notice = error.localizedDescription
        }
    }

    func stopPreview(_ role: CameraRole) {
        channel(for: role).stop()
        notice = "Preview stopped for \(role.title)"
    }

    func takeManualPhoto(_ role: CameraRole) {
        Task {
            do {
                let artifact = try await performCapture(role)
                lastCaptures[role] = artifact
                notice = "Manual \(role.rawValue) photo saved: \(artifact.dimensions.label), \(artifact.byteCount) bytes"
            } catch {
                notice = "Manual capture failed: \(error.localizedDescription)"
            }
        }
    }

    func beginUnattendedAccess(minutes: Int) {
        guard CameraRole.allCases.contains(where: { configuration.mapping(for: $0).automationAllowed }) else {
            notice = "Allow at least one camera for automation first"
            return
        }
        guard let selectedSession, PGCSessionID.isValid(selectedSession),
              knownSessions.contains(selectedSession) else {
            notice = "First request a photo from PGC, then select that session for authorization"
            return
        }
        policy.grant(to: selectedSession, for: TimeInterval(minutes * 60))
        grantedSession = policy.grantedSession
        unattendedUntil = policy.unattendedUntil
        notice = "PGC session \(selectedSession) authorized for up to \(min(minutes, 360)) minutes. Revoke at any time."
    }

    func revokeUnattendedAccess() {
        policy.revoke()
        unattendedUntil = nil
        grantedSession = nil
        if let role = automatedCaptureRole { channel(for: role).stop() }
        notice = "Unattended access revoked; any active automated capture was cancelled"
    }

    func isUnattendedActive(at date: Date = Date()) -> Bool {
        guard let grantedSession else { return false }
        return policy.isActive(for: grantedSession, at: date)
    }

    func performAutomatedRequest(_ request: CaptureRequest) async -> CaptureResponse {
        if !knownSessions.contains(request.session) {
            knownSessions.insert(request.session, at: 0)
            if knownSessions.count > 12 { knownSessions.removeLast() }
            if selectedSession == nil { selectedSession = request.session }
        }
        notice = "PGC session \(request.session) requested \(request.camera.rawValue); checking authorization"
        if let denied = policy.authorize(request.camera, session: request.session, configuration: configuration) {
            notice = "Automation DENIED for \(request.camera.rawValue) / \(request.session): \(denied.rawValue)"
            return .failure(denied.rawValue, "A.P.P.L.E.P.I.E. has not authorized unattended capture of \(request.camera.rawValue)", camera: request.camera)
        }
        guard cameraAuthorization == .authorized,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return .failure("camera_permission_denied", "macOS Camera permission is not authorized", camera: request.camera)
        }
        guard isConnected(request.camera) else {
            return .failure("camera_disconnected", "Assigned camera is not connected", camera: request.camera)
        }
        guard activeCapture == nil else {
            return .failure("capture_busy", "Another still capture is already underway", camera: request.camera)
        }
        notice = "● AUTOMATED CAPTURE REQUESTED: \(request.camera.rawValue)"
        automatedCaptureRole = request.camera
        defer { automatedCaptureRole = nil }
        do {
            let artifact = try await performCapture(request.camera, origin: .pgc, session: request.session)
            lastCaptures[request.camera] = artifact
            notice = "● Automated \(request.camera.rawValue) photo saved; available to authorized local client"
            return artifact.response
        } catch {
            notice = "Automated capture failed: \(error.localizedDescription)"
            return .failure("capture_failed", error.localizedDescription, camera: request.camera)
        }
    }

    private func performCapture(_ role: CameraRole, origin: CaptureOrigin = .manual, session: String? = nil) async throws -> CaptureArtifact {
        guard activeCapture == nil else { throw CameraCaptureError(message: "Another capture is already in progress") }
        guard cameraAuthorization == .authorized,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraCaptureError(message: "macOS Camera access is not authorized")
        }
        guard let mappingID = configuration.mapping(for: role).deviceID,
              isConnected(role) else {
            throw CameraCaptureError(message: "Assigned camera is missing or disconnected")
        }
        guard let fileStore else { throw CameraCaptureError(message: "Capture storage is unavailable") }
        activeCapture = role
        notice = "● CAPTURING \(role.rawValue.uppercased())"
        defer { activeCapture = nil }
        let bytes = try await channel(for: role).capture(
            deviceID: mappingID, resolution: configuration.mapping(for: role).resolution
        )
        let artifact = try fileStore.saveJPEG(bytes, role: role)
        let record = CaptureHistoryEntry(artifact: artifact, origin: origin, session: session)
        captureHistory.insert(record, at: 0)
        do {
            guard let historyStore else { throw CameraCaptureError(message: "Capture history storage is unavailable") }
            try historyStore.append(record)
            historyWarning = nil
        } catch {
            historyWarning = "Photo saved but history could not be persisted: \(error.localizedDescription)"
        }
        // Old images are short-lived; newly saved images remain available for the handoff.
        try? fileStore.purgeOlderThan(Date().addingTimeInterval(-10 * 60))
        return artifact
    }

    func reveal(_ role: CameraRole) {
        guard let artifact = lastCaptures[role] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artifact.filename)])
    }

    func isHistoryPhotoAvailable(_ record: CaptureHistoryEntry) -> Bool {
        FileManager.default.fileExists(atPath: record.filename)
    }

    func revealHistoryPhoto(_ record: CaptureHistoryEntry) {
        guard isHistoryPhotoAvailable(record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.filename)])
    }

    private func startSocket() {
        do {
            let url = try LocalCaptureSocket.defaultSocketURL()
            let server = LocalCaptureSocket(socketURL: url) { [weak self] request in
                guard let self else { return .failure("app_unavailable", "A.P.P.L.E.P.I.E. is shutting down") }
                return await self.performAutomatedRequest(request)
            }
            try server.start()
            socket = server
            socketStatus = "LOCAL SOCKET LISTENING · \(url.path) · user-only · automation locked by default"
        } catch {
            socketStatus = "LOCAL SOCKET UNAVAILABLE: \(error.localizedDescription)"
        }
    }
}
