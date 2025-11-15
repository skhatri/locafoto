import SwiftUI
import AVFoundation

@MainActor
class CameraViewModel: NSObject, ObservableObject {
    @Published var captureSession = AVCaptureSession()
    @Published var isCapturing = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    private var photoOutput = AVCapturePhotoOutput()
    private var cameraService: CameraService?
    private var encryptionService = EncryptionService()
    private var storageService = StorageService()

    /// Check camera permissions
    func checkPermissions() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                errorMessage = "Camera access is required to capture photos"
                showErrorAlert = true
            }
        case .denied, .restricted:
            errorMessage = "Please enable camera access in Settings"
            showErrorAlert = true
        @unknown default:
            break
        }
    }

    /// Start the camera session
    func startCamera() async {
        do {
            cameraService = CameraService()
            try await cameraService?.setupCamera(session: captureSession, output: photoOutput)
        } catch {
            errorMessage = "Failed to start camera: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Stop the camera session
    func stopCamera() {
        cameraService?.stopCamera(session: captureSession)
    }

    /// Capture a photo
    func capturePhoto() async {
        guard !isCapturing else { return }

        isCapturing = true

        do {
            // Capture photo data
            guard let photoData = await cameraService?.capturePhoto(output: photoOutput) else {
                throw CameraError.captureFailed
            }

            // Generate thumbnail using utility
            let thumbnailData = try ThumbnailGenerator.generate(from: photoData)

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

}

enum CameraError: LocalizedError {
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Failed to capture photo"
        }
    }
}
