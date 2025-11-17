import SwiftUI
import AVFoundation

@MainActor
class CameraViewModel: NSObject, ObservableObject {
    @Published var captureSession = AVCaptureSession()
    @Published var isCapturing = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?
    @Published var isCameraReady = false
    @Published var needsPermission = false
    @Published var cameraStatusMessage = "Initializing camera..."

    private var photoOutput = AVCapturePhotoOutput()
    private var cameraService: CameraService?
    private var encryptionService = EncryptionService()
    private var storageService = StorageService()

    /// Check camera permissions
    func checkPermissions() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            needsPermission = false
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                needsPermission = true
                cameraStatusMessage = "Camera access is required to capture photos"
                isCameraReady = false
            } else {
                needsPermission = false
            }
        case .denied, .restricted:
            needsPermission = true
            cameraStatusMessage = "Please enable camera access in Settings to use the camera"
            isCameraReady = false
        @unknown default:
            break
        }
    }

    /// Start the camera session
    func startCamera() async {
        // Don't start camera if permission denied
        if needsPermission {
            return
        }

        do {
            cameraService = CameraService()
            try await cameraService?.setupCamera(session: captureSession, output: photoOutput)
            isCameraReady = true
            cameraStatusMessage = ""
        } catch {
            isCameraReady = false
            cameraStatusMessage = "Failed to start camera: \(error.localizedDescription)"
            errorMessage = cameraStatusMessage
        }
    }

    /// Stop the camera session
    func stopCamera() {
        Task {
            await cameraService?.stopCamera(session: captureSession)
        }
    }

    /// Capture a photo
    func capturePhoto() async {
        guard !isCapturing else { return }

        isCapturing = true

        do {
            // Capture photo data
            guard let photoData = try await cameraService?.capturePhoto(output: photoOutput) else {
                throw CameraError.captureFailed
            }

            // Generate thumbnail
            let thumbnailData = try generateThumbnail(from: photoData)

            // Encrypt both full image and thumbnail
            let encryptedPhoto = try await encryptionService.encryptPhoto(photoData)
            let encryptedThumbnail = try await encryptionService.encryptPhotoData(
                thumbnailData,
                encryptedKey: encryptedPhoto.encryptedKey,
                iv: encryptedPhoto.iv,
                authTag: encryptedPhoto.authTag
            )

            // Save to storage
            try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail)

            // Show success
            isCapturing = false
            showSuccessAlert = true

        } catch {
            errorMessage = "Failed to save photo: \(error.localizedDescription)"
            isCapturing = false
            showErrorAlert = true
        }
    }

    /// Generate thumbnail from photo data
    private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw CameraError.invalidImageData
        }

        let scale = size / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.8) else {
            throw CameraError.thumbnailGenerationFailed
        }

        return thumbnailData
    }
}

enum CameraError: LocalizedError {
    case captureFailed
    case invalidImageData
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Failed to capture photo"
        case .invalidImageData:
            return "Invalid image data"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}
