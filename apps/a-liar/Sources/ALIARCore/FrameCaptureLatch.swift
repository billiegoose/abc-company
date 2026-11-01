import Foundation

/// Consumes one explicitly requested preview frame; never encodes idle video frames.
public final class FrameCaptureLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var armedRequest: UInt64?

    public init() {}

    public func arm(request: UInt64) {
        lock.lock()
        armedRequest = request
        lock.unlock()
    }

    public func consume() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        let request = armedRequest
        armedRequest = nil
        return request
    }

    public func reset() {
        lock.lock()
        armedRequest = nil
        lock.unlock()
    }
}
