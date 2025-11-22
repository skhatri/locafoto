import Foundation
import PhotosUI
import UIKit
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

/// Service for importing photos from Camera Roll
actor PhotoImportService {
    private let storageService = StorageService()
    private let trackingService = LFSFileTrackingService()

    /// Get current thumbnail style from settings
    private var thumbnailStyle: ThumbnailStyle {
        let rawValue = UserDefaults.standard.integer(forKey: "thumbnailStyle")
        return ThumbnailStyle(rawValue: rawValue) ?? .blurred
    }

    /// Maximum video size in bytes (100MB)
    private static let maxVideoSize: Int64 = 100 * 1024 * 1024

    /// Import a single photo or video from PHPickerResult with specified encryption key
    func importPhoto(_ result: PHPickerResult, encryptionKey: SymmetricKey, keyName: String, albumId: UUID) async throws {
        // Check if it's a video
        if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            try await importVideo(result, encryptionKey: encryptionKey, keyName: keyName, albumId: albumId)
            return
        }

        // Load the image data
        let photoData = try await loadPhotoData(from: result)

        // Generate thumbnail based on style setting
        let style = thumbnailStyle
        let thumbnailData = try generateThumbnail(from: photoData, style: style)

        // Encrypt full image with the LFS key
        let photoId = UUID()
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(photoData, using: encryptionKey, nonce: nonce)

        // Encrypt thumbnail with master key for fast gallery loading
        let encryptionService = EncryptionService()
        let encryptedThumbnail = try await encryptionService.encryptPhoto(thumbnailData)

        // Create encrypted photo structure
        // Store thumbnail encryption info (master key based) in the Photo metadata
        // Full image decryption uses LFS key looked up via tracking service
        let encryptedPhoto = EncryptedPhoto(
            id: photoId,
            encryptedData: sealedBox.ciphertext,
            encryptedKey: encryptedThumbnail.encryptedKey, // For thumbnail decryption
            iv: encryptedThumbnail.iv, // For thumbnail decryption
            authTag: encryptedThumbnail.authTag, // For thumbnail decryption
            metadata: PhotoMetadata(
                originalSize: photoData.count,
                captureDate: Date(),
                width: nil,
                height: nil,
                format: "IMPORTED"
            )
        )

        // Save encrypted thumbnail
        try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail.encryptedData, albumId: albumId)

        // Track the import with key name and full image nonce/tag
        try await trackingService.trackImportWithCrypto(
            photoId: photoId,
            keyName: keyName,
            originalFilename: "import_\(photoId.uuidString)",
            fileSize: Int64(photoData.count),
            iv: Data(nonce),
            authTag: sealedBox.tag
        )
    }

    /// Import a video from PHPickerResult
    private func importVideo(_ result: PHPickerResult, encryptionKey: SymmetricKey, keyName: String, albumId: UUID) async throws {
        // Load video data
        let videoData = try await loadVideoData(from: result)

        // Check size limit
        guard videoData.count <= Self.maxVideoSize else {
            throw ImportError.videoTooLarge
        }

        // Generate thumbnail from video
        let style = thumbnailStyle
        let thumbnailData = try generateVideoThumbnail(from: videoData, style: style)

        // Encrypt video with the LFS key
        let photoId = UUID()
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(videoData, using: encryptionKey, nonce: nonce)

        // Encrypt thumbnail with master key
        let encryptionService = EncryptionService()
        let encryptedThumbnail = try await encryptionService.encryptPhoto(thumbnailData)

        // Create encrypted photo structure
        let encryptedPhoto = EncryptedPhoto(
            id: photoId,
            encryptedData: sealedBox.ciphertext,
            encryptedKey: encryptedThumbnail.encryptedKey,
            iv: encryptedThumbnail.iv,
            authTag: encryptedThumbnail.authTag,
            metadata: PhotoMetadata(
                originalSize: videoData.count,
                captureDate: Date(),
                width: nil,
                height: nil,
                format: "VIDEO"
            )
        )

        // Save encrypted thumbnail
        try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail.encryptedData, albumId: albumId)

        // Track the import
        try await trackingService.trackImportWithCrypto(
            photoId: photoId,
            keyName: keyName,
            originalFilename: "video_\(photoId.uuidString)",
            fileSize: Int64(videoData.count),
            iv: Data(nonce),
            authTag: sealedBox.tag
        )
    }

    /// Load video data from PHPickerResult
    private func loadVideoData(from result: PHPickerResult) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = url else {
                    continuation.resume(throwing: ImportError.noVideoData)
                    return
                }

                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate thumbnail from video
    private func generateVideoThumbnail(from data: Data, style: ThumbnailStyle) throws -> Data {
        // Write video to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Generate thumbnail from first frame
        let asset = AVAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let image = UIImage(cgImage: cgImage)

        // Resize and optionally blur
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw ImportError.thumbnailGenerationFailed
        }

        return try generateThumbnail(from: imageData, style: style)
    }

    /// Load photo data from PHPickerResult
    private func loadPhotoData(from result: PHPickerResult) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: ImportError.noImageData)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    /// Generate thumbnail from photo data with style
    private func generateThumbnail(from data: Data, style: ThumbnailStyle) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImportError.invalidImageData
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
            throw ImportError.thumbnailGenerationFailed
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

// MARK: - Errors

enum ImportError: LocalizedError {
    case noImageData
    case noVideoData
    case videoTooLarge
    case invalidImageData
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "No image data available"
        case .noVideoData:
            return "No video data available"
        case .videoTooLarge:
            return "Video exceeds 100MB size limit"
        case .invalidImageData:
            return "Invalid image data"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}
