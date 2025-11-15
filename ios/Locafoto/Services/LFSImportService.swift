import Foundation
import CryptoKit
import UIKit

/// Service for importing .lfs files shared via AirDrop
actor LFSImportService {
    private let keyManagementService = KeyManagementService()
    private let storageService = StorageService()
    private let trackingService = LFSFileTrackingService()

    /// Handle incoming .lfs file from AirDrop
    func handleIncomingLFSFile(from url: URL, pin: String) async throws -> Photo {
        // Read the LFS file
        let fileData = try Data(contentsOf: url)
        let originalFilename = url.lastPathComponent

        // Parse LFS structure
        let lfsFile = try LFSFile.parse(from: fileData)

        print("📥 Received LFS file with key name: '\(lfsFile.keyName)'")

        // Get the encryption key by name
        let encryptionKey = try await keyManagementService.getKey(byName: lfsFile.keyName, pin: pin)

        // Decrypt the file
        let nonce = try AES.GCM.Nonce(data: lfsFile.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: lfsFile.encryptedData,
            tag: lfsFile.tag
        )

        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

        // Determine if it's an image
        guard let image = UIImage(data: decryptedData) else {
            throw LFSError.invalidFormat
        }

        // Generate thumbnail
        let thumbnailData = try generateThumbnail(from: decryptedData)

        // Now re-encrypt with our own encryption system for storage
        let encryptionService = EncryptionService()
        let encryptedPhoto = try await encryptionService.encryptPhoto(decryptedData)
        let encryptedThumbnail = try await encryptionService.encryptPhotoData(
            thumbnailData,
            encryptedKey: encryptedPhoto.encryptedKey,
            iv: encryptedPhoto.iv,
            authTag: encryptedPhoto.authTag
        )

        // Save to storage
        try await storageService.savePhoto(encryptedPhoto, thumbnail: encryptedThumbnail)

        // Create Photo object
        let photo = Photo(
            id: encryptedPhoto.id,
            encryptedKeyData: encryptedPhoto.encryptedKey,
            ivData: encryptedPhoto.iv,
            authTagData: encryptedPhoto.authTag,
            captureDate: Date(),
            importDate: Date(),
            modifiedDate: Date(),
            originalSize: Int64(decryptedData.count),
            encryptedSize: Int64(encryptedPhoto.encryptedData.count),
            width: Int32(image.size.width),
            height: Int32(image.size.height),
            format: "LFS",
            filePath: "",
            thumbnailPath: nil,
            tags: ["lfs", "imported"],
            isFavorite: false,
            isHidden: false
        )

        // Track this import for key usage statistics
        try await trackingService.trackImport(
            photoId: photo.id,
            keyName: lfsFile.keyName,
            originalFilename: originalFilename,
            fileSize: Int64(fileData.count)
        )

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)

        return photo
    }

    /// Export a photo as .lfs file for sharing
    func createLFSFile(
        for photo: Photo,
        keyName: String,
        pin: String
    ) async throws -> URL {
        // Load the photo data (encrypted)
        let encryptedPhotoData = try await storageService.loadPhoto(for: photo.id)

        // Decrypt the photo (to re-encrypt with LFS key)
        let encryptionService = EncryptionService()
        let decryptedData = try await encryptionService.decryptPhotoData(
            encryptedPhotoData,
            encryptedKey: photo.encryptedKeyData,
            iv: photo.ivData,
            authTag: photo.authTagData
        )

        // Get the LFS encryption key
        let lfsKey = try await keyManagementService.getKey(byName: keyName, pin: pin)

        // Encrypt with LFS key
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(decryptedData, using: lfsKey, nonce: nonce)

        // Create LFS file
        let lfsFileData = try LFSFile.create(
            keyName: keyName,
            encryptedData: sealedBox.ciphertext,
            nonce: Data(nonce),
            tag: sealedBox.tag
        )

        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(photo.id.uuidString).lfs"
        let fileURL = tempDir.appendingPathComponent(filename)

        try lfsFileData.write(to: fileURL)

        return fileURL
    }

    /// Generate thumbnail from photo data
    private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw LFSError.invalidFormat
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
            throw LFSError.invalidFormat
        }

        return thumbnailData
    }
}
