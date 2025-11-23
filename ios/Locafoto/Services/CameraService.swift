import AVFoundation
import UIKit

/// Service for capturing photos directly without saving to Camera Roll
actor CameraService: NSObject {
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var currentPosition: AVCaptureDevice.Position = .back

    /// Set up the camera session
    func setupCamera(session: AVCaptureSession, output: AVCapturePhotoOutput, position: AVCaptureDevice.Position = .back) throws {
        currentPosition = position
        session.beginConfiguration()

        // Set session preset for photo quality
        session.sessionPreset = .photo

        // Get the camera for specified position
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
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
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// Flip camera between front and back
    func flipCamera(session: AVCaptureSession, output: AVCapturePhotoOutput) throws {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back

        session.beginConfiguration()

        // Remove existing input
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }

        // Get camera for new position
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            session.commitConfiguration()
            throw CameraServiceError.cameraNotAvailable
        }

        // Add new input
        let newInput = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentPosition = newPosition
        } else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }

        session.commitConfiguration()
    }

    /// Get current camera position
    func getCurrentPosition() -> AVCaptureDevice.Position {
        return currentPosition
    }

    /// Stop the camera session
    func stopCamera(session: AVCaptureSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// Capture a photo and return the data
    /// IMPORTANT: This never saves to Camera Roll!
    func capturePhoto(output: AVCapturePhotoOutput) async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: CameraServiceError.captureFailed)
                return
            }

            Task {
                await self.setPhotoContinuation(continuation)

                // Use HEIC if available for better compression
                let settings: AVCapturePhotoSettings
                if output.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    settings.isHighResolutionPhotoEnabled = true
                } else {
                    settings = AVCapturePhotoSettings()
                    settings.isHighResolutionPhotoEnabled = true
                }
                
                // Set photo orientation to portrait
                if let connection = output.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        // Get current device orientation
                        let deviceOrientation = UIDevice.current.orientation
                        let photoOrientation: AVCaptureVideoOrientation
                        
                        switch deviceOrientation {
                        case .portrait:
                            photoOrientation = .portrait
                        case .portraitUpsideDown:
                            photoOrientation = .portraitUpsideDown
                        case .landscapeLeft:
                            photoOrientation = .landscapeRight
                        case .landscapeRight:
                            photoOrientation = .landscapeLeft
                        default:
                            photoOrientation = .portrait
                        }
                        
                        connection.videoOrientation = photoOrientation
                    }
                }

                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func setPhotoContinuation(_ continuation: CheckedContinuation<Data, Error>) {
        self.photoContinuation = continuation
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
    case captureFailed

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
        case .captureFailed:
            return "Camera capture failed"
        }
    }
}
