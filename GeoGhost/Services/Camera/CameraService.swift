@preconcurrency import AVFoundation
import Foundation
import Observation
import UIKit

/// AVFoundation photo capture with GPS written into the file's EXIF.
@Observable
@MainActor
final class CameraService: NSObject {
    enum State: Equatable { case idle, configuring, running, unavailable(String), denied }

    private(set) var state: State = .idle
    private(set) var isFlashAvailable = false
    var flashMode: AVCaptureDevice.FlashMode = .off
    private(set) var zoomFactor: CGFloat = 1

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.passerbo.geoghost.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var pendingCapture: CheckedContinuation<Data, Error>?
    private var delegateBox: PhotoDelegate?

    var isRunning: Bool { state == .running }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { state = .denied; return }
        case .denied, .restricted:
            state = .denied
            return
        default: break
        }
        guard state != .running, state != .configuring else { return }
        state = .configuring
        let session = self.session
        let output = self.photoOutput
        let result: Result<(AVCaptureDevice, Bool), CameraError> = await withCheckedContinuation { cont in
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                defer { session.commitConfiguration() }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video) else {
                    cont.resume(returning: .failure(.noCamera)); return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    for i in session.inputs { session.removeInput(i) }
                    guard session.canAddInput(input) else { cont.resume(returning: .failure(.configuration)); return }
                    session.addInput(input)
                    if !session.outputs.contains(output) {
                        guard session.canAddOutput(output) else { cont.resume(returning: .failure(.configuration)); return }
                        session.addOutput(output)
                    }
                    output.maxPhotoQualityPrioritization = .balanced
                    cont.resume(returning: .success((device, device.hasFlash)))
                } catch {
                    cont.resume(returning: .failure(.configuration))
                }
            }
        }
        switch result {
        case .success(let (device, hasFlash)):
            self.device = device
            self.isFlashAvailable = hasFlash
            sessionQueue.async { session.startRunning() }
            state = .running
        case .failure(let err):
            state = .unavailable(err.localizedDescription)
        }
    }

    func stop() {
        let session = self.session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
        if state == .running { state = .idle }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = min(max(1, factor), min(device.activeFormat.videoMaxZoomFactor, 6))
        zoomFactor = clamped
        sessionQueue.async {
            do { try device.lockForConfiguration(); device.videoZoomFactor = clamped; device.unlockForConfiguration() } catch {}
        }
    }

    func focus(atDevicePoint point: CGPoint) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point; device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// Capture a still. Returns encoded file bytes (HEIC when available) with GPS/EXIF embedded.
    func capturePhoto(metadata: CaptureMetadata) async throws -> Data {
        guard state == .running else { throw CameraError.notRunning }
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        if isFlashAvailable { settings.flashMode = flashMode }
        settings.photoQualityPrioritization = .balanced
        if let lat = metadata.latitude, let lon = metadata.longitude {
            settings.metadata[kCGImagePropertyGPSDictionary as String] = ImageMetadataReader.gpsDictionary(
                latitude: lat, longitude: lon, altitude: metadata.altitude, accuracy: metadata.horizontalAccuracy,
                heading: metadata.heading, date: metadata.capturedAt ?? Date())
        }
        let output = photoOutput
        return try await withCheckedThrowingContinuation { cont in
            let delegate = PhotoDelegate { result in
                Task { @MainActor in
                    self.delegateBox = nil
                    cont.resume(with: result)
                }
            }
            self.delegateBox = delegate
            sessionQueue.async {
                if let connection = output.connection(with: .video) {
                    let angle: CGFloat = 90 // portrait
                    if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                }
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

enum CameraError: LocalizedError {
    case noCamera, configuration, notRunning, noData
    var errorDescription: String? {
        switch self {
        case .noCamera: String(localized: "No camera is available on this device.")
        case .configuration: String(localized: "The camera could not be configured.")
        case .notRunning: String(localized: "The camera is not ready.")
        case .noData: String(localized: "The photo could not be read.")
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Result<Data, Error>) -> Void
    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { completion(.failure(error)); return }
        guard let data = photo.fileDataRepresentation() else { completion(.failure(CameraError.noData)); return }
        completion(.success(data))
    }
}
