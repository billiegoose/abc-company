import AppKit
import AVFoundation
import SwiftUI
import ALIARCore

@main
struct APPLEPIEApp: App {
    @StateObject private var lab = LabModel()

    var body: some Scene {
        WindowGroup(AppIdentity.name) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppIdentity.name).font(.largeTitle.monospaced()).bold()
                            Text(AppIdentity.fullName).font(.headline)
                            Text("Anana Banana Computing Company · Experimental Systems Division")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(lab.activeCapture == nil ? "OBSERVATION READY" : "● CAPTURE IN PROGRESS",
                              systemImage: lab.activeCapture == nil ? "eye" : "record.circle.fill")
                            .font(.headline.monospaced())
                            .foregroundStyle(lab.activeCapture == nil ? Color.secondary : Color.red)
                    }
                    PermissionBar(lab: lab)
                    HStack(alignment: .top, spacing: 16) {
                        InstrumentPanel(role: .board, lab: lab, channel: lab.boardChannel)
                        InstrumentPanel(role: .monitor, lab: lab, channel: lab.monitorChannel)
                    }
                    AutomationPanel(lab: lab)
                    CaptureHistoryPanel(lab: lab)
                    Text(lab.notice)
                        .font(.callout.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(22)
            }
            .frame(minWidth: 1050, minHeight: 720)
        }
    }
}

private struct PermissionBar: View {
    @ObservedObject var lab: LabModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lab.cameraAuthorization == .authorized ? "checkmark.shield" : "lock.shield")
            Text(permissionDescription)
            Spacer()
            Button("Refresh devices") { lab.refreshDevices() }
            if lab.cameraAuthorization == .notDetermined {
                Button("Grant macOS Camera Access") { lab.askForCameraPermission() }
                    .buttonStyle(.borderedProminent)
            }
            if lab.cameraAuthorization == .denied || lab.cameraAuthorization == .restricted {
                Button("Open Camera Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionDescription: String {
        switch lab.cameraAuthorization {
        case .authorized: "macOS Camera permission: authorized for A.P.P.L.E.P.I.E."
        case .notDetermined: "macOS Camera permission: not requested (no camera opened)"
        case .denied: "macOS Camera permission: denied"
        case .restricted: "macOS Camera permission: restricted"
        @unknown default: "macOS Camera permission: unknown"
        }
    }
}

private struct InstrumentPanel: View {
    let role: CameraRole
    @ObservedObject var lab: LabModel
    @ObservedObject var channel: CameraChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(role == .board ? "01 / BOARD" : "02 / MONITOR").font(.headline.monospaced())
            Text(role.title).foregroundStyle(.secondary)
            Picker("Physical webcam", selection: Binding<String?>(
                get: { lab.configuration.mapping(for: role).deviceID },
                set: { lab.assignDevice($0, to: role) }
            )) {
                Text("Not assigned").tag(Optional<String>.none)
                ForEach(lab.devices, id: \.uniqueID) { device in
                    Text(device.localizedName + " [" + String(device.uniqueID.suffix(8)) + "]")
                        .tag(Optional(device.uniqueID))
                }
                if let id = lab.configuration.mapping(for: role).deviceID,
                   !lab.devices.contains(where: { $0.uniqueID == id }) {
                    Text("Disconnected [" + String(id.suffix(8)) + "]")
                        .tag(Optional(id))
                }
            }
            .pickerStyle(.menu)
            Picker("Preview / JPEG resolution", selection: Binding<PixelDimensions?>(
                get: { lab.configuration.mapping(for: role).resolution },
                set: { lab.chooseResolution($0, for: role) }
            )) {
                Text("Highest supported").tag(Optional<PixelDimensions>.none)
                ForEach(lab.resolutions(for: role)) { dimensions in
                    Text(dimensions.label).tag(Optional(dimensions))
                }
            }
            .pickerStyle(.menu)
            .disabled(!lab.isConnected(role))
            ZStack {
                CameraPreview(session: channel.session)
                    .frame(height: 260)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if !channel.isPreviewing {
                    Text(lab.isConnected(role) ? "PREVIEW OFF" : "CAMERA UNAVAILABLE")
                        .foregroundStyle(.white)
                        .font(.title3.monospaced())
                        .padding(10)
                }
                if channel.isCapturing {
                    VStack {
                        HStack {
                            Label("● CAPTURING", systemImage: "record.circle.fill")
                                .font(.headline.monospaced())
                                .padding(8)
                                .background(.red, in: RoundedRectangle(cornerRadius: 6))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            HStack {
                Button(channel.isPreviewing ? "Stop preview" : "Start preview") {
                    if channel.isPreviewing { lab.stopPreview(role) } else { lab.startPreview(role) }
                }
                Button("Capture JPEG") { lab.takeManualPhoto(role) }
                    .buttonStyle(.borderedProminent)
                    .disabled(lab.activeCapture != nil)
            }
            .disabled(!lab.isConnected(role) || lab.cameraAuthorization != .authorized)
            Text(channel.status).font(.caption).foregroundStyle(.secondary)
            if let capture = lab.lastCaptures[role] {
                HStack {
                    Text("Latest: \(capture.dimensions.label) · \(capture.byteCount) bytes")
                        .font(.caption.monospaced())
                    Spacer()
                    Button("Reveal JPEG") { lab.reveal(role) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AutomationPanel: View {
    @ObservedObject var lab: LabModel
    @State private var grantMinutes = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("LOCAL AUTOMATION AUTHORIZATION", systemImage: "lock.shield")
                .font(.headline.monospaced())
            Text("Denied by default. Enable each camera separately, then grant one identified PGC session access for up to six hours. Session grants are never stored across app launches.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Requesting PGC session", selection: $lab.selectedSession) {
                    Text("Awaiting a PGC camera request").tag(Optional<String>.none)
                    ForEach(lab.knownSessions, id: \.self) { session in
                        Text(session).tag(Optional(session))
                    }
                }
                .frame(maxWidth: 540)
                Text("Only the selected session receives the grant")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                ForEach(CameraRole.allCases) { role in
                    Toggle("Permit \(role.rawValue) still photos", isOn: Binding(
                        get: { lab.configuration.mapping(for: role).automationAllowed },
                        set: { lab.allowAutomation($0, for: role) }
                    ))
                    .disabled(lab.configuration.mapping(for: role).deviceID == nil)
                }
            }
            HStack {
                Picker("Grant duration", selection: $grantMinutes) {
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                    Text("6 hours (maximum)").tag(360)
                }
                .frame(maxWidth: 260)
                Button("Authorize Unattended Capture") { lab.beginUnattendedAccess(minutes: grantMinutes) }
                    .disabled(lab.selectedSession == nil || !CameraRole.allCases.contains(where: { lab.configuration.mapping(for: $0).automationAllowed }))
                Button("Revoke Now") { lab.revokeUnattendedAccess() }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if let expiry = lab.unattendedUntil, lab.isUnattendedActive(at: timeline.date) {
                        Text("● \(lab.grantedSession ?? "?") GRANTED until \(expiry.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.red).font(.headline.monospaced())
                    } else {
                        Text("AUTOMATION LOCKED")
                            .foregroundStyle(.secondary).font(.headline.monospaced())
                    }
                }
            }
            Text(lab.socketStatus).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}
