import AVFoundation
import UIKit

/// Service for capturing photos directly without saving to Camera Roll
actor CameraService: NSObject {
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Set up the camera session
    func setupCamera(session: AVCaptureSession, output: AVCapturePhotoOutput) throws {
        session.beginConfiguration()

        // Get the back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraServiceError.cameraNotAvailable
        }

        // Create input from camera
        let input = try AVCaptureDeviceInput(device: camera)

        // Add input to session
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw CameraServiceError.cannotAddInput
        }

        // Add output to session
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw CameraServiceError.cannotAddOutput
        }

        // Configure photo output
        output.isHighResolutionCaptureEnabled = true
        if output.availablePhotoCodecTypes.contains(.hevc) {
            // Prefer HEIC format for better compression
            output.setPreparedPhotoSettingsArray([
                AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            ])
        }

        session.commitConfiguration()

        // Start the session on background thread
        Task {
            session.startRunning()
        }
    }

    /// Stop the camera session
    func stopCamera(session: AVCaptureSession) {
        Task {
            session.stopRunning()
        }
    }

    /// Capture a photo and return the data
    /// IMPORTANT: This never saves to Camera Roll!
    func capturePhoto(output: AVCapturePhotoOutput) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            var settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true

            // Use HEIC if available for better compression
            let settings: AVCapturePhotoSettings
            if output.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                settings.isHighResolutionPhotoEnabled = true
            } else {
                settings = AVCapturePhotoSettings()
                settings.isHighResolutionPhotoEnabled = true
            }

            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task {
            await handlePhotoCapture(photo: photo, error: error)
        }
    }

    private func handlePhotoCapture(photo: AVCapturePhoto, error: Error?) {
        guard let continuation = photoContinuation else { return }
        photoContinuation = nil

        if let error = error {
            continuation.resume(throwing: error)
            return
        }

        // Get the photo data - THIS STAYS IN MEMORY, never saved to Camera Roll
        guard let imageData = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CameraServiceError.noImageData)
            return
        }

        // Return the data - it will be encrypted and saved to app container
        continuation.resume(returning: imageData)
    }
}

// MARK: - Errors

enum CameraServiceError: LocalizedError {
    case cameraNotAvailable
    case cannotAddInput
    case cannotAddOutput
    case noImageData

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add photo output to session"
        case .noImageData:
            return "Failed to get image data from photo"
        }
    }
}
