import Foundation
import CryptoKit
import UIKit

/// Service for importing .lfs files shared via AirDrop
actor LFSImportService {
    private let keyManagementService = KeyManagementService()
    private let storageService = StorageService()
    private let trackingService = LFSFileTrackingService()
    private let albumService = AlbumService.shared

    /// Handle incoming .lfs file from AirDrop
    func handleIncomingLFSFile(from url: URL, pin: String) async throws -> Photo {
        // Ensure we can access the file
        let hasAccess = url.startAccessingSecurityScopedResource()
        if !hasAccess {
            print("⚠️ Warning: Could not access security-scoped resource")
        }
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Read the LFS file
        let fileData = try Data(contentsOf: url)
        let originalFilename = url.lastPathComponent

        // Parse LFS structure
        let lfsFile = try LFSFile.parse(from: fileData)

        print("📥 Received LFS file with key name: '\(lfsFile.keyName)'")

        // Get the encryption key by name
        let encryptionKey = try await keyManagementService.getKey(byName: lfsFile.keyName, pin: pin)

        // Find target album: prefer matching key, then main album (default gallery), then any album
        try await albumService.loadAlbums()
        let albums = await albumService.getAllAlbums()
        
        // Priority: 1) Album with matching key, 2) Main album (default gallery), 3) Any album
        let targetAlbum = albums.first(where: { $0.keyName == lfsFile.keyName })
            ?? albums.first(where: { $0.isMain })
            ?? albums.first

        guard let targetAlbum = targetAlbum else {
            throw LFSError.noAlbumAvailable
        }
        
        let albumId = targetAlbum.id
        print("📁 Saving .lfs file to album: '\(targetAlbum.name)' (main: \(targetAlbum.isMain))")

        // Decrypt the file temporarily to validate and generate thumbnail
        let nonce = try AES.GCM.Nonce(data: lfsFile.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: lfsFile.encryptedData,
            tag: lfsFile.tag
        )

        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

        // Validate decrypted data is an image
        guard !decryptedData.isEmpty else {
            print("❌ Decrypted data is empty")
            throw LFSError.invalidImageData("Decrypted data is empty")
        }

        guard let image = UIImage(data: decryptedData) else {
            // Log details for debugging
            let prefix = decryptedData.prefix(16).map { String(format: "%02x", $0) }.joined()
            print("❌ Failed to create UIImage from decrypted data")
            print("   Data size: \(decryptedData.count) bytes")
            print("   Data prefix: \(prefix)")
            throw LFSError.invalidImageData("Cannot decode image data (\(decryptedData.count) bytes)")
        }

        // Validate image dimensions
        guard image.size.width > 0 && image.size.height > 0 else {
            print("❌ Image has invalid dimensions: \(image.size)")
            throw LFSError.invalidImageData("Image has zero dimensions")
        }

        print("✅ Validated image: \(Int(image.size.width))x\(Int(image.size.height))")

        // Generate thumbnail
        let thumbnailData = try generateThumbnail(from: decryptedData)

        // CRITICAL: Main photo stays encrypted with LFS key (store original encrypted data)
        // Only thumbnail gets encrypted with master key for fast gallery loading
        let encryptionService = EncryptionService()
        
        // Encrypt thumbnail with master key for fast gallery loading
        let encryptedThumbnail = try await encryptionService.encryptPhoto(thumbnailData)
        
        // Create photo ID
        let photoId = UUID()
        
        // Create encrypted photo structure
        // Main photo: Stored AS-IS from LFS file (still encrypted with LFS key)
        // Thumbnail: Encrypted with master key - store thumbnail encryption info
        // Main photo encryption info is tracked separately via LFSFileTrackingService
        let encryptedPhotoForStorage = EncryptedPhoto(
            id: photoId,
            encryptedData: lfsFile.encryptedData, // Store original LFS-encrypted data (LFS key)
            encryptedKey: encryptedThumbnail.encryptedKey, // Thumbnail key (for backward compat)
            iv: encryptedThumbnail.iv, // Thumbnail IV (for backward compat)
            authTag: encryptedThumbnail.authTag, // Thumbnail authTag (for backward compat)
            // Thumbnail encryption info (separate)
            thumbnailEncryptedKey: encryptedThumbnail.encryptedKey,
            thumbnailIv: encryptedThumbnail.iv,
            thumbnailAuthTag: encryptedThumbnail.authTag,
            metadata: PhotoMetadata(
                originalSize: decryptedData.count,
                captureDate: Date(),
                width: Int(image.size.width),
                height: Int(image.size.height),
                format: "LFS"
            )
        )

        // Save to storage - savePhoto will create the Photo object
        try await storageService.savePhoto(encryptedPhotoForStorage, thumbnail: encryptedThumbnail.encryptedData, albumId: albumId)

        // Load the Photo object that was created by savePhoto
        let photo = await PhotoStore.shared.get(encryptedPhotoForStorage.id)
        
        guard let photo = photo else {
            throw LFSError.importFailed("Photo was saved but could not be retrieved")
        }

        // Track this import with LFS key encryption info (IV and authTag from LFS file)
        // This allows decryption of the main photo using LFS key
        try await trackingService.trackImportWithCrypto(
            photoId: photo.id,
            keyName: lfsFile.keyName,
            originalFilename: originalFilename,
            fileSize: Int64(fileData.count),
            iv: lfsFile.nonce, // IV from LFS file
            authTag: lfsFile.tag // AuthTag from LFS file
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
        let nonce = AES.GCM.Nonce()
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

    /// Create a share bundle for an entire album (all photos as .lfs + .lfkey)
    func createAlbumShareBundle(for album: Album, pin: String) async throws -> [URL] {
        var shareURLs: [URL] = []

        // Get all photos in the album
        let photos = await PhotoStore.shared.getPhotos(forAlbum: album.id)

        guard !photos.isEmpty else {
            throw LFSError.importFailed("Album has no photos to share")
        }

        // Export the album's encryption key as .lfkey
        let keyURL = try await keyManagementService.exportKey(byName: album.keyName, pin: pin)
        shareURLs.append(keyURL)

        // Export each photo as .lfs file
        for photo in photos {
            let lfsURL = try await createLFSFile(for: photo, keyName: album.keyName, pin: pin)
            shareURLs.append(lfsURL)
        }

        return shareURLs
    }

    /// Generate thumbnail from photo data
    private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw LFSError.invalidImageData("Cannot create image for thumbnail")
        }

        // Validate dimensions
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > 0 else {
            throw LFSError.invalidImageData("Image has zero dimensions for thumbnail")
        }

        let scale = size / maxDim
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let thumbnail = thumbnail else {
            throw LFSError.invalidImageData("Failed to create thumbnail context")
        }

        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw LFSError.invalidImageData("Failed to encode thumbnail as JPEG")
        }

        print("✅ Generated thumbnail: \(Int(newSize.width))x\(Int(newSize.height)), \(thumbnailData.count) bytes")

        return thumbnailData
    }
}
