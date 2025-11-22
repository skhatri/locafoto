import Foundation
import UIKit

/// Service for loading seed/test data on first app install
actor SeedDataService {
    private let encryptionService = EncryptionService()
    private let storageService = StorageService()
    private let albumService = AlbumService.shared

    /// Key for tracking if seed data has been loaded
    private static let seedDataLoadedKey = "com.locafoto.seedDataLoaded"

    /// Bundled seed images to encrypt on first launch
    private static let seedImages = [
        "logo1",
        "logo2"
    ]

    /// Check if seed data needs to be loaded and load it
    func loadSeedDataIfNeeded() async {
        // Check if already loaded
        let loaded = UserDefaults.standard.bool(forKey: Self.seedDataLoadedKey)
        if loaded {
            return
        }

        do {
            try await loadSeedData()
            UserDefaults.standard.set(true, forKey: Self.seedDataLoadedKey)
            print("✅ Seed data loaded successfully")
        } catch {
            print("❌ Failed to load seed data: \(error)")
        }
    }

    /// Load and encrypt all seed images
    private func loadSeedData() async throws {
        for imageName in Self.seedImages {
            try await loadAndEncryptSeedImage(named: imageName)
        }
    }

    /// Load a single seed image from bundle and encrypt it
    private func loadAndEncryptSeedImage(named name: String) async throws {
        // Try to load from bundle with various extensions
        guard let imageData = loadImageData(named: name) else {
            print("⚠️ Could not find seed image: \(name)")
            return
        }

        // Get main album for seed data
        try await albumService.loadAlbums()
        let albums = await albumService.getAllAlbums()
        guard let mainAlbum = albums.first(where: { $0.isMain }) ?? albums.first else {
            print("⚠️ No album available for seed data")
            return
        }

        // Encrypt the photo with master key
        let encryptedPhoto = try await encryptionService.encryptPhoto(imageData)

        // Generate thumbnail
        let thumbnail = generateThumbnail(from: imageData) ?? imageData

        // Encrypt thumbnail separately with master key (gets its own IV/authTag)
        let encryptedThumbnail = try await encryptionService.encryptPhoto(thumbnail)

        // Create EncryptedPhoto with both sets of encryption info
        let encryptedPhotoForStorage = EncryptedPhoto(
            id: encryptedPhoto.id,
            encryptedData: encryptedPhoto.encryptedData,
            encryptedKey: encryptedPhoto.encryptedKey, // Main photo's key
            iv: encryptedPhoto.iv, // Main photo's IV
            authTag: encryptedPhoto.authTag, // Main photo's authTag
            // Thumbnail encryption info (separate)
            thumbnailEncryptedKey: encryptedThumbnail.encryptedKey,
            thumbnailIv: encryptedThumbnail.iv,
            thumbnailAuthTag: encryptedThumbnail.authTag,
            metadata: PhotoMetadata(
                originalSize: imageData.count,
                captureDate: Date(),
                width: nil,
                height: nil,
                format: "SEED"
            )
        )

        // Save to storage
        try await storageService.savePhoto(encryptedPhotoForStorage, thumbnail: encryptedThumbnail.encryptedData, albumId: mainAlbum.id)

        print("✅ Loaded seed image: \(name)")
    }

    /// Load image data from bundle
    private func loadImageData(named name: String) -> Data? {
        // Try common image extensions
        let extensions = ["webp", "jpeg", "jpg", "png", "heic"]

        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }

        // Try loading as UIImage (handles various formats)
        if let image = UIImage(named: name),
           let data = image.jpegData(compressionQuality: 0.9) {
            return data
        }

        return nil
    }

    /// Generate a thumbnail from image data
    private func generateThumbnail(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }

        let thumbnailSize = CGSize(width: 200, height: 200)
        let scale = min(
            thumbnailSize.width / image.size.width,
            thumbnailSize.height / image.size.height
        )

        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnailImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return thumbnailImage.jpegData(compressionQuality: 0.7)
    }

    /// Reset seed data state (for testing)
    func resetSeedDataState() {
        UserDefaults.standard.removeObject(forKey: Self.seedDataLoadedKey)
    }
}
