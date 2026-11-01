import Darwin
import Foundation

public enum LocalSocketError: Error, LocalizedError {
    case pathTooLong
    case socketAlreadyRunning
    case occupiedByOtherFile
    case occupiedByOtherUser
    case systemCall(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong: "Unix socket path exceeds macOS limits"
        case .socketAlreadyRunning: "A.P.P.L.E.P.I.E. socket server is already running"
        case .occupiedByOtherFile: "Socket path is occupied by a non-socket file"
        case .occupiedByOtherUser: "Socket path belongs to another user"
        case .systemCall(let name, let code): "\(name) failed (errno \(code))"
        }
    }
}

/// A local, one-request-per-connection JSON-line socket. Never opens cameras itself.
public final class LocalCaptureSocket: @unchecked Sendable {
    public typealias Handler = @Sendable (CaptureRequest) async -> CaptureResponse

    public let socketURL: URL
    private let handler: Handler
    private let lock = NSLock()
    private var listeningFD: Int32 = -1
    private var lockFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "com.ananabanana.APPLEPIE.socket.accept")
    private let clientQueue = DispatchQueue(label: "com.ananabanana.APPLEPIE.socket.client", attributes: .concurrent)

    public init(socketURL: URL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    public static func defaultSocketURL() throws -> URL {
        try ConfigurationStore.defaultStore().fileURL
            .deletingLastPathComponent().appendingPathComponent("capture.sock")
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listeningFD == -1 else { throw LocalSocketError.socketAlreadyRunning }
        let path = socketURL.path
        let pathBytes = Array(path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw LocalSocketError.pathTooLong
        }
        let parent = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let guardFD = Darwin.open(parent.appendingPathComponent("capture.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard guardFD >= 0 else { throw LocalSocketError.systemCall("open lock", errno) }
        guard flock(guardFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(guardFD)
            throw LocalSocketError.socketAlreadyRunning
        }
        defer {
            if listeningFD == -1 {
                flock(guardFD, LOCK_UN)
                Darwin.close(guardFD)
            }
        }
        var current = stat()
        if lstat(path, &current) == 0 {
            guard (current.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) else {
                throw LocalSocketError.occupiedByOtherFile
            }
            guard current.st_uid == getuid() else { throw LocalSocketError.occupiedByOtherUser }
            guard unlink(path) == 0 else { throw LocalSocketError.systemCall("unlink", errno) }
        } else if errno != ENOENT {
            throw LocalSocketError.systemCall("lstat", errno)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalSocketError.systemCall("socket", errno) }
        do {
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                bytes.copyBytes(from: pathBytes.map(UInt8.init))
            }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw LocalSocketError.systemCall("bind", errno) }
            guard chmod(path, 0o600) == 0 else { throw LocalSocketError.systemCall("chmod", errno) }
            guard Darwin.listen(fd, 8) == 0 else { throw LocalSocketError.systemCall("listen", errno) }
            listeningFD = fd
            lockFD = guardFD
            acceptQueue.async { [weak self] in self?.acceptLoop(fd: fd) }
        } catch {
            Darwin.close(fd)
            unlink(path)
            throw error
        }
    }

    public func stop() {
        lock.lock()
        let fd = listeningFD
        let oldLockFD = lockFD
        listeningFD = -1
        lockFD = -1
        lock.unlock()
        guard fd >= 0 else { return }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        unlink(socketURL.path)
        if oldLockFD >= 0 {
            flock(oldLockFD, LOCK_UN)
            Darwin.close(oldLockFD)
        }
    }

    deinit { stop() }

    private func acceptLoop(fd: Int32) {
        while true {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            clientQueue.async { [weak self] in
                if let self { self.handleClient(client) }
                else { Darwin.close(client) }
            }
        }
    }

    private func handleClient(_ client: Int32) {
        var noSIGPIPE: Int32 = 1
        withUnsafePointer(to: &noSIGPIPE) {
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            sendResponse(.failure("peer_not_authorized", "Only a process belonging to the app user may connect"), to: client)
            return
        }
        let payload: Data
        do {
            payload = try readLine(from: client)
        } catch {
            let code = (error as? ProtocolError) == .oversized ? "request_too_large" : "invalid_request"
            sendResponse(.failure(code, "Missing newline, oversized request, or read timeout"), to: client)
            return
        }
        let request: CaptureRequest
        do {
            request = try CaptureProtocol.decodeRequest(payload)
        } catch {
            let code: String
            switch error {
            case ProtocolError.oversized: code = "request_too_large"
            case ProtocolError.unsupportedVersion: code = "unsupported_version"
            case ProtocolError.unsupportedCommand: code = "unsupported_command"
            default: code = "invalid_request"
            }
            sendResponse(.failure(code, "Invalid or unsupported capture request"), to: client)
            return
        }
        Task.detached { [handler, weak self] in
            let response = await handler(request)
            guard let self else { Darwin.close(client); return }
            self.sendResponse(response, to: client)
        }
    }

    private func readLine(from client: Int32) throws -> Data {
        var buffer = Data()
        while buffer.count <= CaptureProtocol.maximumRequestBytes {
            var byte: UInt8 = 0
            let count = Darwin.recv(client, &byte, 1, 0)
            guard count == 1 else { throw ProtocolError.invalidJSON }
            if byte == 0x0A { return buffer }
            buffer.append(byte)
        }
        throw ProtocolError.oversized
    }

    private func sendResponse(_ response: CaptureResponse, to client: Int32) {
        defer { Darwin.close(client) }
        guard let bytes = try? CaptureProtocol.encodeResponse(response) else { return }
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.send(client, base.advanced(by: offset), buffer.count - offset, 0)
                if count <= 0 { return }
                offset += count
            }
        }
    }
}

/// Small testable client; a future PGC bridge can use the same newline protocol.
public enum LocalCaptureClient {
    public static func request(_ request: CaptureRequest, socketURL: URL) throws -> CaptureResponse {
        try sendRaw(CaptureProtocol.encodeRequest(request), socketURL: socketURL)
    }

    public static func sendRaw(_ request: Data, socketURL: URL) throws -> CaptureResponse {
        let pathBytes = Array(socketURL.path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw LocalSocketError.pathTooLong
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalSocketError.systemCall("socket", errno) }
        defer { Darwin.close(fd) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes.map(UInt8.init)) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw LocalSocketError.systemCall("connect", errno) }
        var timeout = timeval(tv_sec: 25, tv_usec: 0)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        let written = request.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        guard written == request.count else { throw LocalSocketError.systemCall("send", errno) }
        var bytes = Data()
        while bytes.count < 4096 {
            var byte: UInt8 = 0
            let received = Darwin.recv(fd, &byte, 1, 0)
            guard received == 1 else { throw ProtocolError.invalidJSON }
            if byte == 0x0A { break }
            bytes.append(byte)
        }
        guard bytes.count < 4096 else { throw ProtocolError.oversized }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CaptureResponse.self, from: bytes)
    }
}
