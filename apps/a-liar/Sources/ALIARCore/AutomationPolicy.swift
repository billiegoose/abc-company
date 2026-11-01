import Foundation

public enum AutomationDenial: String, Equatable, Error, Sendable {
    case cameraNotMapped = "camera_not_mapped"
    case cameraNotAllowed = "camera_not_allowed"
    case sessionNotGranted = "session_not_granted"
    case unattendedAccessInactive = "unattended_access_inactive"
}

public enum PGCSessionID {
    public static func isValid(_ session: String) -> Bool {
        let bytes = Array(session.utf8)
        guard !bytes.isEmpty && bytes.count <= 128 else { return false }
        let alphanumeric: (UInt8) -> Bool = { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard alphanumeric(bytes[0]) else { return false }
        return bytes.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 58 || $0 == 95 }
    }
}

/// Deliberately memory-only: restarting A.P.P.L.E.P.I.E. revokes the session-specific grant.
public struct AutomationPolicy: Sendable {
    public static let maximumDuration: TimeInterval = 6 * 60 * 60
    public private(set) var grantedSession: String?
    public private(set) var unattendedUntil: Date?

    public init() {}

    /// At most one PGC routing session can hold the camera grant at a time.
    public mutating func grant(to session: String, for duration: TimeInterval, now: Date = Date()) {
        guard PGCSessionID.isValid(session) else { revoke(); return }
        grantedSession = session
        unattendedUntil = now.addingTimeInterval(max(0, min(duration, Self.maximumDuration)))
    }

    public mutating func revoke() {
        grantedSession = nil
        unattendedUntil = nil
    }

    public func isActive(for session: String, at date: Date = Date()) -> Bool {
        guard grantedSession == session, let unattendedUntil else { return false }
        return date < unattendedUntil
    }

    public func authorize(_ role: CameraRole, session: String, configuration: AppConfiguration, now: Date = Date()) -> AutomationDenial? {
        let mapping = configuration.mapping(for: role)
        guard mapping.deviceID != nil else { return .cameraNotMapped }
        guard mapping.automationAllowed else { return .cameraNotAllowed }
        guard grantedSession == session else { return .sessionNotGranted }
        guard isActive(for: session, at: now) else { return .unattendedAccessInactive }
        return nil
    }
}
