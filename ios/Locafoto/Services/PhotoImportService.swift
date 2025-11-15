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

}

// MARK: - Errors

enum ImportError: LocalizedError {
    case noImageData
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "No image data available"
        case .invalidImageData:
            return "Invalid image data"
        }
    }
}
