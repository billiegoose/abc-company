import AppKit
import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import ALIARCore

struct CameraCaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class CameraChannel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isCapturing = false
    @Published private(set) var status = "Preview is off"

    private var currentDeviceID: String?
    private var requestedResolution: PixelDimensions?
    private var videoOutput: AVCaptureVideoDataOutput?
    nonisolated let frameLatch = FrameCaptureLatch()
    private var pending: CheckedContinuation<Data, Error>?
    private var deadline: Task<Void, Never>?
    private var warmupTimer: Task<Void, Never>?
    private var previewStartedAt: Date?
    private var captureSequence: UInt64 = 0
    private var activeSequence: UInt64?

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let reason = ns.localizedFailureReason.map { "; \($0)" } ?? ""
        return "\(ns.localizedDescription) [\(ns.domain):\(ns.code)]\(reason)"
    }

    static func connectedDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    static func resolutions(for device: AVCaptureDevice) -> [PixelDimensions] {
        let dimensions = device.formats.map { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return PixelDimensions(width: Int(size.width), height: Int(size.height))
        }
        return Array(Set(dimensions.filter(\.isReasonable))).sorted {
            let a = Int64($0.width) * Int64($0.height)
            let b = Int64($1.width) * Int64($1.height)
            return a == b ? $0.width < $1.width : a < b
        }
    }

    func startPreview(deviceID: String, resolution: PixelDimensions?) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraCaptureError(message: "macOS Camera access has not been granted to A.P.P.L.E.P.I.E.")
        }
        if isPreviewing && currentDeviceID == deviceID && requestedResolution == resolution { return }
        stop()
        guard let device = Self.connectedDevices().first(where: { $0.uniqueID == deviceID }) else {
            throw CameraCaptureError(message: "Assigned camera is disconnected")
        }
        let chosenResolution = resolution ?? Self.resolutions(for: device).last
        guard let chosenResolution, chosenResolution.isReasonable else {
            throw CameraCaptureError(message: "No supported video-preview resolution")
        }
        guard let format = device.formats.first(where: { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(size.width) == chosenResolution.width && Int(size.height) == chosenResolution.height
        }) else {
            throw CameraCaptureError(message: "Selected resolution is no longer supported by this camera")
        }

        do { try device.lockForConfiguration() }
        catch { throw CameraCaptureError(message: "Cannot configure camera: \(Self.describe(error))") }
        device.activeFormat = format
        device.unlockForConfiguration()

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) }
        catch {
            captureSession.commitConfiguration()
            throw CameraCaptureError(message: "Cannot open camera input: \(Self.describe(error))")
        }
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw CameraCaptureError(message: "Cannot connect camera input")
        }
        captureSession.addInput(input)
        // The preview and JPEG use the same video samples; no separate photo pipeline.
        let frames = AVCaptureVideoDataOutput()
        frames.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(frames) else {
            captureSession.commitConfiguration()
            throw CameraCaptureError(message: "Cannot create webcam frame output")
        }
        captureSession.addOutput(frames)
        frames.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.ananabanana.APPLEPIE.video-frames"))
        captureSession.commitConfiguration()

        currentDeviceID = deviceID
        requestedResolution = resolution
        videoOutput = frames
        session = captureSession
        status = "Starting preview…"
        // Start only after an explicit UI preview/capture action; never during app launch.
        captureSession.startRunning()
        isPreviewing = captureSession.isRunning
        previewStartedAt = isPreviewing ? Date() : nil
        status = isPreviewing ? "Live preview" : "Camera did not start"
        if !isPreviewing { throw CameraCaptureError(message: status) }
        let actual = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if Int(actual.width) != chosenResolution.width || Int(actual.height) != chosenResolution.height {
            stop()
            throw CameraCaptureError(message: "macOS changed the webcam format; selected preview resolution is unavailable")
        }
    }

    func stop() {
        if pending != nil {
            finish(.failure(CameraCaptureError(message: "Capture cancelled because the camera stopped")))
        }
        frameLatch.reset()
        session?.stopRunning()
        session = nil
        videoOutput = nil
        currentDeviceID = nil
        requestedResolution = nil
        previewStartedAt = nil
        isPreviewing = false
        status = "Preview is off"
    }

    func capture(deviceID: String, resolution: PixelDimensions?) async throws -> Data {
        guard !isCapturing else { throw CameraCaptureError(message: "A capture is already in progress") }
        do { try startPreview(deviceID: deviceID, resolution: resolution) }
        catch { throw CameraCaptureError(message: "Preview setup failed: \(Self.describe(error))") }
        guard videoOutput != nil, isPreviewing else {
            throw CameraCaptureError(message: "Camera preview frame output is unavailable")
        }
        // A webcam's auto-exposure may need a moment after the stream first starts.
        // Existing previews are reused immediately, including automatic resolution selection.
        let previewAge = Date().timeIntervalSince(previewStartedAt ?? .distantPast)
        let warmupSeconds = max(0, 1.5 - previewAge)
        status = "● CAPTURING PREVIEW FRAME"
        isCapturing = true
        captureSequence &+= 1
        let sequence = captureSequence
        activeSequence = sequence
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(CaptureProtocol.captureTimeout)) }
                catch { return }
                self?.finish(.failure(CameraCaptureError(message: "Preview frame capture timed out")))
            }
            if warmupSeconds > 0 {
                warmupTimer = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(warmupSeconds)) }
                    catch { return }
                    guard let self, self.pending != nil, self.activeSequence == sequence else { return }
                    self.frameLatch.arm(request: sequence)
                }
            } else {
                frameLatch.arm(request: sequence)
            }
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sequence = frameLatch.consume() else { return }
        let jpeg: Data?
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            jpeg = CIContext().jpegRepresentation(
                of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [:]
            )
        } else {
            jpeg = nil
        }
        Task { @MainActor [weak self] in
            guard self?.activeSequence == sequence else { return }
            if let jpeg { self?.finish(.success(jpeg)) }
            else { self?.finish(.failure(CameraCaptureError(message: "Live video frame could not be encoded as JPEG"))) }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let pending else { return }
        self.pending = nil
        activeSequence = nil
        frameLatch.reset()
        warmupTimer?.cancel()
        warmupTimer = nil
        deadline?.cancel()
        deadline = nil
        isCapturing = false
        switch result {
        case .success:
            status = "Preview frame saved as JPEG"
        case .failure(let error):
            status = "Capture failed: \(error.localizedDescription)"
        }
        pending.resume(with: result)
    }
}

final class PreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> PreviewNSView { PreviewNSView(frame: .zero) }
    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.previewLayer.session = session
    }
}
