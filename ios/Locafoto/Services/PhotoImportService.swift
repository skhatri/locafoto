import Foundation
import PhotosUI
import UIKit

/// Service for importing photos from Camera Roll
actor PhotoImportService {
    private let encryptionService = EncryptionService()
    private let storageService = StorageService()

    /// Import a single photo from PHPickerResult
    func importPhoto(_ result: PHPickerResult) async throws {
        // Load the image data
        let photoData = try await loadPhotoData(from: result)

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

    /// Generate thumbnail from photo data
    private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImportError.invalidImageData
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
            throw ImportError.thumbnailGenerationFailed
        }

        return thumbnailData
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case noImageData
    case invalidImageData
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "No image data available"
        case .invalidImageData:
            return "Invalid image data"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}
