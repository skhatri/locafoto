import Foundation
import UniformTypeIdentifiers
import UIKit

/// Service for sharing encrypted photos via AirDrop
actor SharingService {
    private let storageService = StorageService()

    // MARK: - Export for Sharing

    /// Create a .locaphoto bundle file for sharing
    func createShareBundle(for photo: Photo) async throws -> URL {
        // Load encrypted photo data
        let photoData = try await storageService.loadPhoto(for: photo.id)

        // Create share bundle structure
        let bundle = ShareBundle(
            version: "1.0",
            photo: ShareBundle.PhotoData(
                id: photo.id.uuidString,
                encryptedData: photoData.base64EncodedString(),
                encryptedKey: photo.encryptedKeyData.base64EncodedString(),
                iv: photo.ivData.base64EncodedString(),
                authTag: photo.authTagData.base64EncodedString()
            ),
            metadata: ShareBundle.Metadata(
                originalSize: Int(photo.originalSize),
                captureDate: ISO8601DateFormatter().string(from: photo.captureDate),
                width: photo.width != nil ? Int(photo.width!) : nil,
                height: photo.height != nil ? Int(photo.height!) : nil,
                format: photo.format
            )
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(bundle)

        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(photo.id.uuidString).locaphoto"
        let fileURL = tempDir.appendingPathComponent(filename)

        try jsonData.write(to: fileURL)

        return fileURL
    }

    // MARK: - Import from Share

    /// Handle incoming .locaphoto file
    func handleIncomingShare(from url: URL) async throws -> Photo {
        // Read the bundle file
        let jsonData = try Data(contentsOf: url)

        // Decode bundle
        let decoder = JSONDecoder()
        let bundle = try decoder.decode(ShareBundle.self, from: jsonData)

        // Validate version
        guard bundle.version == "1.0" else {
            throw SharingError.unsupportedVersion
        }

        // Decode base64 data
        guard let photoData = Data(base64Encoded: bundle.photo.encryptedData),
              let encryptedKey = Data(base64Encoded: bundle.photo.encryptedKey),
              let iv = Data(base64Encoded: bundle.photo.iv),
              let authTag = Data(base64Encoded: bundle.photo.authTag),
              let photoID = UUID(uuidString: bundle.photo.id) else {
            throw SharingError.invalidBundleFormat
        }

        // Decrypt the photo to generate thumbnail
        let encryptionService = EncryptionService()
        let decryptedData = try await encryptionService.decryptPhotoData(
            photoData,
            encryptedKey: encryptedKey,
            iv: iv,
            authTag: authTag
        )

        // Generate thumbnail
        let thumbnailData = try generateThumbnail(from: decryptedData)

        // Encrypt the thumbnail with the same key/iv/tag
        let encryptedThumbnail = try await encryptionService.encryptPhotoData(
            thumbnailData,
            encryptedKey: encryptedKey,
            iv: iv,
            authTag: authTag
        )

        // Create photo object
        let photo = Photo(
            id: photoID,
            encryptedKeyData: encryptedKey,
            ivData: iv,
            authTagData: authTag,
            captureDate: ISO8601DateFormatter().date(from: bundle.metadata.captureDate) ?? Date(),
            importDate: Date(),
            modifiedDate: Date(),
            originalSize: Int64(bundle.metadata.originalSize),
            encryptedSize: Int64(photoData.count),
            width: bundle.metadata.width.map { Int32($0) },
            height: bundle.metadata.height.map { Int32($0) },
            format: bundle.metadata.format,
            filePath: "",
            thumbnailPath: nil,
            tags: [],
            isFavorite: false,
            isHidden: false
        )

        // Save the encrypted photo with thumbnail
        try await storageService.saveSharedPhoto(photo, encryptedData: photoData, thumbnail: encryptedThumbnail)

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)

        return photo
    }

    /// Generate thumbnail from photo data
    private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw SharingError.invalidBundleFormat
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
            throw SharingError.invalidBundleFormat
        }

        return thumbnailData
    }
}

// MARK: - Share Bundle Structure

struct ShareBundle: Codable {
    let version: String

    struct PhotoData: Codable {
        let id: String
        let encryptedData: String
        let encryptedKey: String
        let iv: String
        let authTag: String
    }

    struct Metadata: Codable {
        let originalSize: Int
        let captureDate: String
        let width: Int?
        let height: Int?
        let format: String
    }

    let photo: PhotoData
    let metadata: Metadata
}

// MARK: - Errors

enum SharingError: LocalizedError {
    case unsupportedVersion
    case invalidBundleFormat
    case importFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This share bundle version is not supported"
        case .invalidBundleFormat:
            return "Invalid share bundle format"
        case .importFailed:
            return "Failed to import shared photo"
        }
    }
}
