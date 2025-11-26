import SwiftUI
import AVFoundation
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Camera capture mode
enum CaptureMode: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"
}

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

    // Video recording state
    @Published var captureMode: CaptureMode = .photo
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var pendingVideoURL: URL?  // Holds video URL when auto-stopped
    @Published var selectedVideoFilter: VideoFilterPreset = .none
    private var recordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 30

    private var photoOutput = AVCapturePhotoOutput()
    private var cameraService: CameraService?
    private var storageService = StorageService()
    private var keyManagementService = KeyManagementService()
    private var trackingService = LFSFileTrackingService()
    private var albumService = AlbumService.shared
    private var filterService = FilterService()

    // Preview rendering
    var previewView: MetalPreviewView?

    /// Check camera and microphone permissions
    func checkPermissions() async {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch videoStatus {
        case .authorized:
            needsPermission = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                needsPermission = true
                cameraStatusMessage = "Camera access is required to capture photos and videos"
                isCameraReady = false
                return
            } else {
                needsPermission = false
            }
        case .denied, .restricted:
            needsPermission = true
            cameraStatusMessage = "Please enable camera access in Settings to use the camera"
            isCameraReady = false
            return
        @unknown default:
            break
        }

        // Request microphone access for video recording
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    /// Start the camera session
    func startCamera() async {
        // Don't start camera if permission denied
        if needsPermission {
            return
        }

        // Don't start if already running
        if captureSession.isRunning {
            isCameraReady = true
            return
        }

        do {
            // Create fresh photo output for this session
            photoOutput = AVCapturePhotoOutput()
            cameraService = CameraService()

            // Set up frame callback for preview
            await cameraService?.setPreviewCallback { [weak self] ciImage in
                DispatchQueue.main.async {
                    self?.previewView?.renderFrame(ciImage)
                }
            }

            try await cameraService?.setupCamera(session: captureSession, output: photoOutput)
            isCameraReady = true
            cameraStatusMessage = ""
        } catch {
            isCameraReady = false
            cameraStatusMessage = "Failed to start camera: \(error.localizedDescription)"
            errorMessage = cameraStatusMessage
        }
    }

    /// Stop the camera session and clean up resources
    func stopCamera() {
        // Stop running first
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        // Remove all inputs and outputs to allow fresh setup next time
        captureSession.beginConfiguration()

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        captureSession.commitConfiguration()

        // Reset state
        isCameraReady = false
        cameraService = nil
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
            
            // Note: We don't mirror saved photos - AVCapturePhotoOutput handles orientation via EXIF
            // The preview is mirrored for user experience, but saved photos should match standard camera behavior
            // If user wants mirrored selfies, they can flip in post-processing

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

    // MARK: - Video Recording

    /// Start video recording
    func startRecording() async {
        guard !isRecording else { return }

        guard selectedKeyName != nil else {
            errorMessage = "Please select an encryption key first"
            ToastManager.shared.showError("Please select an encryption key first")
            return
        }

        guard selectedAlbumId != nil else {
            errorMessage = "Please select an album first"
            ToastManager.shared.showError("Please select an album first")
            return
        }

        do {
            // Set video filter before starting
            await cameraService?.setVideoFilter(selectedVideoFilter)

            try await cameraService?.startRecording()
            isRecording = true
            recordingDuration = 0

            // Start timer to track duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.recordingDuration += 0.1

                    // Auto-stop at max duration
                    if self.recordingDuration >= self.maxRecordingDuration {
                        await self.autoStopRecording()
                    }
                }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            ToastManager.shared.showError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Auto-stop recording when max duration reached
    private func autoStopRecording() async {
        guard isRecording else { return }

        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        do {
            guard let videoURL = try await cameraService?.stopRecording() else {
                throw CameraError.captureFailed
            }

            isRecording = false
            pendingVideoURL = videoURL

            // Show message to user
            ToastManager.shared.showSuccess("Recording complete - tap to save")

        } catch {
            isRecording = false
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
            ToastManager.shared.showError("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    /// Stop video recording and save
    func stopRecording(pin: String) async {
        // Check if we have a pending video from auto-stop
        if let videoURL = pendingVideoURL {
            pendingVideoURL = nil
            isCapturing = true
            await saveVideo(from: videoURL, pin: pin)
            isCapturing = false
            return
        }

        guard isRecording else { return }

        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        do {
            guard let videoURL = try await cameraService?.stopRecording() else {
                throw CameraError.captureFailed
            }

            isRecording = false
            isCapturing = true

            // Save the video
            await saveVideo(from: videoURL, pin: pin)

            isCapturing = false

        } catch {
            isRecording = false
            isCapturing = false
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
            ToastManager.shared.showError("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    /// Save recorded video with encryption
    private func saveVideo(from videoURL: URL, pin: String) async {
        guard let keyName = selectedKeyName,
              let albumId = selectedAlbumId else {
            ToastManager.shared.showError("No key or album selected")
            return
        }

        do {
            // Read video data
            let videoData = try Data(contentsOf: videoURL)

            // Get video duration
            let asset = AVAsset(url: videoURL)
            let duration = try await asset.load(.duration).seconds

            // Get the encryption key
            let encryptionKey = try await keyManagementService.getKey(byName: keyName, pin: pin)

            // Generate thumbnail from video
            let thumbnailData = try await generateVideoThumbnail(from: videoURL)

            // Generate thumbnail based on style setting
            let styleRaw = UserDefaults.standard.integer(forKey: "thumbnailStyle")
            let style = ThumbnailStyle(rawValue: styleRaw) ?? .blurred
            let processedThumbnail = try processThumbnail(thumbnailData, style: style)

            // Encrypt video with the selected LFS key
            let videoId = UUID()
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(videoData, using: encryptionKey, nonce: nonce)

            // Encrypt thumbnail with master key for fast gallery loading
            let encryptionService = EncryptionService()
            let encryptedThumbnail = try await encryptionService.encryptPhoto(processedThumbnail)

            // Create encrypted photo structure (works for videos too)
            let encryptedPhoto = EncryptedPhoto(
                id: videoId,
                encryptedData: sealedBox.ciphertext,
                encryptedKey: encryptedThumbnail.encryptedKey,
                iv: encryptedThumbnail.iv,
                authTag: encryptedThumbnail.authTag,
                thumbnailEncryptedKey: encryptedThumbnail.encryptedKey,
                thumbnailIv: encryptedThumbnail.iv,
                thumbnailAuthTag: encryptedThumbnail.authTag,
                metadata: PhotoMetadata(
                    originalSize: videoData.count,
                    captureDate: Date(),
                    width: nil,
                    height: nil,
                    format: "mov",
                    mediaType: .video,
                    duration: duration
                )
            )

            // Save to storage
            try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail.encryptedData, albumId: albumId)

            // Track the capture with key name and full video crypto info
            try await trackingService.trackImportWithCrypto(
                photoId: videoId,
                keyName: keyName,
                originalFilename: "video_\(videoId.uuidString)",
                fileSize: Int64(videoData.count),
                iv: Data(nonce),
                authTag: sealedBox.tag
            )

            // Clean up temp file
            try? FileManager.default.removeItem(at: videoURL)

            // Show success
            ToastManager.shared.showSuccess("Video encrypted and saved securely")

        } catch {
            ToastManager.shared.showError("Failed to save video: \(error.localizedDescription)")
            // Clean up temp file
            try? FileManager.default.removeItem(at: videoURL)
        }
    }

    /// Generate thumbnail from video
    private func generateVideoThumbnail(from videoURL: URL) async throws -> Data {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        guard let data = uiImage.jpegData(compressionQuality: 0.8) else {
            throw CameraError.thumbnailGenerationFailed
        }

        return data
    }

    /// Process thumbnail with style (blur, etc.)
    private func processThumbnail(_ data: Data, style: ThumbnailStyle) throws -> Data {
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
    
    /// Fix orientation and mirror for front camera selfies
    private func mirrorImageHorizontally(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // First, normalize the image orientation by drawing it
        // This ensures we're working with the actual pixel data, not EXIF orientation
        let size: CGSize
        if image.imageOrientation == .left || image.imageOrientation == .right || 
           image.imageOrientation == .leftMirrored || image.imageOrientation == .rightMirrored {
            // Swap width/height for rotated images
            size = CGSize(width: image.size.height, height: image.size.width)
        } else {
            size = image.size
        }
        
        UIGraphicsBeginImageContextWithOptions(size, true, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Draw image respecting its orientation
        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        
        // Apply orientation transform
        switch image.imageOrientation {
        case .right:
            context.rotate(by: .pi / 2)
        case .left:
            context.rotate(by: -.pi / 2)
        case .down, .downMirrored:
            context.rotate(by: .pi)
        default:
            break
        }
        
        // Mirror if needed (for mirrored orientations)
        if image.imageOrientation == .upMirrored || image.imageOrientation == .downMirrored ||
           image.imageOrientation == .leftMirrored || image.imageOrientation == .rightMirrored {
            context.scaleBy(x: -1, y: 1)
        }
        
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        context.restoreGState()
        
        var normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let normalized = normalizedImage else { return nil }
        
        // Now mirror horizontally for front camera selfie
        guard let ciImage = CIImage(image: normalized) else { return nil }
        let ciContext = CIContext()
        let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
        let translationX = ciImage.extent.width + ciImage.extent.origin.x * 2
        let mirroredImage = ciImage.transformed(by: mirrorTransform.concatenating(CGAffineTransform(translationX: translationX, y: 0)))
        
        guard let cgImage = ciContext.createCGImage(mirroredImage, from: mirroredImage.extent) else {
            return nil
        }
        
        let finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        return finalImage.jpegData(compressionQuality: 0.9)
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
