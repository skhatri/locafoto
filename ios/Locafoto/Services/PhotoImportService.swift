import Foundation
import PhotosUI
import UIKit
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import ImageIO

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

        // Extract metadata from original photo
        let captureDate = extractCaptureDate(from: photoData)
        let dimensions = extractImageDimensions(from: photoData)
        let location = extractLocation(from: photoData)

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

        // Determine format from image data
        let format = detectImageFormat(from: photoData)

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
                captureDate: captureDate,
                width: dimensions?.width,
                height: dimensions?.height,
                format: format,
                latitude: location?.latitude,
                longitude: location?.longitude
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

        // Get video metadata (duration, creation date, location)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try videoData.write(to: tempURL)
        let asset = AVAsset(url: tempURL)
        let duration = try await asset.load(.duration).seconds
        let captureDate = await extractVideoCreationDate(from: tempURL)
        let location = await extractVideoLocation(from: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        // Create encrypted photo structure
        // Main video is encrypted with LFS key (tracked separately via LFSFileTrackingService)
        // Thumbnail is encrypted with master key - store thumbnail encryption info separately
        // For backward compatibility, also store thumbnail encryption in main fields
        // (since main video decryption uses LFS key lookup, not Photo model fields)
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
                originalSize: videoData.count,
                captureDate: captureDate,
                width: nil,
                height: nil,
                format: "mp4",
                mediaType: .video,
                duration: duration,
                latitude: location?.latitude,
                longitude: location?.longitude
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

    /// Extract capture date from image EXIF metadata
    private func extractCaptureDate(from data: Data) -> Date {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return Date()
        }

        // Try EXIF date first
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            if let date = parseExifDate(dateString) {
                return date
            }
        }

        // Try TIFF date
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let dateString = tiff[kCGImagePropertyTIFFDateTime as String] as? String {
            if let date = parseExifDate(dateString) {
                return date
            }
        }

        // Fallback to current date
        return Date()
    }

    /// Parse EXIF date string format "yyyy:MM:dd HH:mm:ss"
    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }

    /// Extract image dimensions from data
    private func extractImageDimensions(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            return nil
        }
        return (width, height)
    }

    /// Extract GPS location from image EXIF metadata
    private func extractLocation(from data: Data) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            return nil
        }

        guard let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            return nil
        }

        // Apply reference directions
        let finalLat = latRef == "S" ? -latitude : latitude
        let finalLon = lonRef == "W" ? -longitude : longitude

        return (finalLat, finalLon)
    }

    /// Extract video location
    private func extractVideoLocation(from url: URL) async -> (latitude: Double, longitude: Double)? {
        let asset = AVAsset(url: url)

        // Try to get location from metadata
        guard let metadata = try? await asset.load(.metadata) else {
            return nil
        }

        for item in metadata {
            if item.commonKey == .commonKeyLocation,
               let value = try? await item.load(.value) as? String {
                // Parse ISO 6709 location string like "+37.7749-122.4194/"
                return parseISO6709Location(value)
            }
        }

        return nil
    }

    /// Parse ISO 6709 location string
    private func parseISO6709Location(_ string: String) -> (latitude: Double, longitude: Double)? {
        // Format: +DD.DDDD+DDD.DDDD/ or +DD.DDDD-DDD.DDDD/
        let pattern = "([+-]?\\d+\\.?\\d*)([+-]\\d+\\.?\\d*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }

        guard let latRange = Range(match.range(at: 1), in: string),
              let lonRange = Range(match.range(at: 2), in: string),
              let latitude = Double(string[latRange]),
              let longitude = Double(string[lonRange]) else {
            return nil
        }

        return (latitude, longitude)
    }

    /// Extract video creation date
    private func extractVideoCreationDate(from url: URL) async -> Date {
        let asset = AVAsset(url: url)
        if let creationDate = try? await asset.load(.creationDate),
           let date = creationDate.dateValue {
            return date
        }
        return Date()
    }

    /// Detect image format from data
    private func detectImageFormat(from data: Data) -> String {
        guard data.count >= 12 else { return "unknown" }

        let bytes = [UInt8](data.prefix(12))

        // JPEG: FFD8FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "jpeg"
        }

        // PNG: 89504E47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "png"
        }

        // HEIC: Check for ftyp box with heic/heix
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
            if brand.lowercased().contains("heic") || brand.lowercased().contains("heix") {
                return "heic"
            }
        }

        // GIF: 474946
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "gif"
        }

        // WebP: RIFF....WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "webp"
        }

        return "unknown"
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
