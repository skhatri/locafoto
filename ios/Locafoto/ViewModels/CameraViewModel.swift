import SwiftUI
import AVFoundation
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
class CameraViewModel: NSObject, ObservableObject {
    @Published var captureSession = AVCaptureSession()
    @Published var isCapturing = false
    @Published var errorMessage: String?
    @Published var isCameraReady = false
    @Published var needsPermission = false
    @Published var cameraStatusMessage = "Initializing camera..."
    @Published var availableKeys: [KeyFile] = []
    @Published var selectedKeyName: String?
    @Published var availableAlbums: [Album] = []
    @Published var selectedAlbumId: UUID?
    @Published var showKeySelection = false
    @Published var isUsingFrontCamera = false
    @Published var selectedFilter: CameraFilterPreset = .none

    private var photoOutput = AVCapturePhotoOutput()
    private var cameraService: CameraService?
    private var storageService = StorageService()
    private var keyManagementService = KeyManagementService()
    private var trackingService = LFSFileTrackingService()
    private var albumService = AlbumService.shared
    private var filterService = FilterService()

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

    /// Flip between front and back camera
    func flipCamera() async {
        do {
            try await cameraService?.flipCamera(session: captureSession, output: photoOutput)
            isUsingFrontCamera.toggle()
        } catch {
            errorMessage = "Failed to flip camera: \(error.localizedDescription)"
            ToastManager.shared.showError("Failed to flip camera: \(error.localizedDescription)")
        }
    }

    /// Load available keys
    func loadKeys() async {
        do {
            availableKeys = try await keyManagementService.loadAllKeys()
            // Auto-select first key if none selected
            if selectedKeyName == nil && !availableKeys.isEmpty {
                selectedKeyName = availableKeys.first?.name
            }
        } catch {
            print("Failed to load keys: \(error)")
            availableKeys = []
        }
    }

    /// Load available albums
    func loadAlbums() async {
        do {
            try await albumService.loadAlbums()
            availableAlbums = await albumService.getAllAlbums()
            // Auto-select main album if none selected
            if selectedAlbumId == nil {
                if let mainAlbum = availableAlbums.first(where: { $0.isMain }) {
                    selectedAlbumId = mainAlbum.id
                    // Also auto-select the album's key
                    selectedKeyName = mainAlbum.keyName
                } else if let firstAlbum = availableAlbums.first {
                    selectedAlbumId = firstAlbum.id
                    selectedKeyName = firstAlbum.keyName
                }
            }
        } catch {
            print("Failed to load albums: \(error)")
            availableAlbums = []
        }
    }

    /// Get selected album
    var selectedAlbum: Album? {
        availableAlbums.first(where: { $0.id == selectedAlbumId })
    }

    /// Capture a photo with selected key
    func capturePhoto(pin: String) async {
        guard !isCapturing else { return }

        guard let keyName = selectedKeyName else {
            errorMessage = "Please select an encryption key first"
            ToastManager.shared.showError("Please select an encryption key first")
            return
        }

        guard let albumId = selectedAlbumId else {
            errorMessage = "Please select an album first"
            ToastManager.shared.showError("Please select an album first")
            return
        }

        isCapturing = true

        do {
            // Get the encryption key
            let encryptionKey = try await keyManagementService.getKey(byName: keyName, pin: pin)

            // Capture photo data
            guard var photoData = try await cameraService?.capturePhoto(output: photoOutput) else {
                throw CameraError.captureFailed
            }

            // Apply filter if selected
            if selectedFilter != .none {
                if let filteredData = filterService.applyFilter(selectedFilter, toPhotoData: photoData) {
                    photoData = filteredData
                }
            }

            // Generate thumbnail based on style setting
            let styleRaw = UserDefaults.standard.integer(forKey: "thumbnailStyle")
            let style = ThumbnailStyle(rawValue: styleRaw) ?? .blurred
            let thumbnailData = try generateThumbnail(from: photoData, style: style)

            // Encrypt full image with the selected LFS key
            let photoId = UUID()
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(photoData, using: encryptionKey, nonce: nonce)

            // Encrypt thumbnail with master key for fast gallery loading
            let encryptionService = EncryptionService()
            let encryptedThumbnail = try await encryptionService.encryptPhoto(thumbnailData)

            // Create encrypted photo structure
            // Main photo is encrypted with LFS key (tracked separately via LFSFileTrackingService)
            // Thumbnail is encrypted with master key - store thumbnail encryption info separately
            // For backward compatibility, also store thumbnail encryption in main fields
            // (since main photo decryption uses LFS key lookup, not Photo model fields)
            let encryptedPhoto = EncryptedPhoto(
                id: photoId,
                encryptedData: sealedBox.ciphertext,
                encryptedKey: encryptedThumbnail.encryptedKey, // Thumbnail key (for backward compat)
                iv: encryptedThumbnail.iv, // Thumbnail IV (for backward compat)
                authTag: encryptedThumbnail.authTag, // Thumbnail authTag (for backward compat)
                // Store thumbnail encryption info separately
                thumbnailEncryptedKey: encryptedThumbnail.encryptedKey,
                thumbnailIv: encryptedThumbnail.iv,
                thumbnailAuthTag: encryptedThumbnail.authTag,
                metadata: PhotoMetadata(
                    originalSize: photoData.count,
                    captureDate: Date(),
                    width: nil,
                    height: nil,
                    format: "CAMERA"
                )
            )

            // Save to storage
            try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail.encryptedData, albumId: albumId)

            // Track the capture with key name and full image crypto info
            try await trackingService.trackImportWithCrypto(
                photoId: photoId,
                keyName: keyName,
                originalFilename: "capture_\(photoId.uuidString)",
                fileSize: Int64(photoData.count),
                iv: Data(nonce),
                authTag: sealedBox.tag
            )

            // Show success
            isCapturing = false
            ToastManager.shared.showSuccess("Photo encrypted and saved securely")

        } catch {
            errorMessage = "Failed to save photo: \(error.localizedDescription)"
            isCapturing = false
            ToastManager.shared.showError("Failed to save photo: \(error.localizedDescription)")
        }
    }

    /// Generate thumbnail from photo data with style
    private func generateThumbnail(from data: Data, style: ThumbnailStyle) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw CameraError.invalidImageData
        }

        let size = style.size
        let scale = size / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        var thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Apply blur if needed
        if style.shouldBlur, let thumbnailImage = thumbnail {
            thumbnail = applyBlur(to: thumbnailImage)
        }

        guard let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.8) else {
            throw CameraError.thumbnailGenerationFailed
        }

        return thumbnailData
    }

    /// Apply blur effect to image
    private func applyBlur(to image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }

        let context = CIContext()
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage
        filter.radius = 3.0  // Subtle blur

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage)
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
