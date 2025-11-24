import Foundation

/// Service for managing encrypted photo storage on the file system
actor StorageService {
    private let fileManager = FileManager.default

    /// Get the base directory for photo storage
    private var photosDirectory: URL {
        get throws {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let locafotoDir = appSupport.appendingPathComponent("Locafoto")

            if !fileManager.fileExists(atPath: locafotoDir.path) {
                try fileManager.createDirectory(at: locafotoDir, withIntermediateDirectories: true)
            }

            return locafotoDir
        }
    }

    private var photosSubdirectory: URL {
        get throws {
            let dir = try photosDirectory.appendingPathComponent("Photos")

            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            return dir
        }
    }

    /// Get the thumbnails subdirectory
    private var thumbnailsSubdirectory: URL {
        get throws {
            let dir = try photosDirectory.appendingPathComponent("Thumbnails")

            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            return dir
        }
    }

    // MARK: - Save Operations

    /// Save an encrypted photo and its thumbnail
    func savePhoto(_ encryptedPhoto: EncryptedPhoto, thumbnail: Data, albumId: UUID) async throws {
        let photoDir = try photosSubdirectory
        let thumbDir = try thumbnailsSubdirectory

        // Create file URLs
        let photoURL = photoDir.appendingPathComponent("\(encryptedPhoto.id.uuidString).encrypted")
        let thumbURL = thumbDir.appendingPathComponent("\(encryptedPhoto.id.uuidString).thumb")

        // Write encrypted photo data
        try encryptedPhoto.encryptedData.write(to: photoURL)

        // Write encrypted thumbnail
        try thumbnail.write(to: thumbURL)

        // Save metadata to persistent store
        let photo = Photo(
            id: encryptedPhoto.id,
            encryptedKeyData: encryptedPhoto.encryptedKey,
            ivData: encryptedPhoto.iv,
            authTagData: encryptedPhoto.authTag,
            // Store thumbnail encryption info if provided, otherwise nil (backward compatible)
            thumbnailEncryptedKeyData: encryptedPhoto.thumbnailEncryptedKey,
            thumbnailIvData: encryptedPhoto.thumbnailIv,
            thumbnailAuthTagData: encryptedPhoto.thumbnailAuthTag,
            captureDate: encryptedPhoto.metadata.captureDate,
            importDate: Date(),
            modifiedDate: Date(),
            originalSize: Int64(encryptedPhoto.metadata.originalSize),
            encryptedSize: Int64(encryptedPhoto.encryptedData.count),
            width: encryptedPhoto.metadata.width.map { Int32($0) },
            height: encryptedPhoto.metadata.height.map { Int32($0) },
            format: encryptedPhoto.metadata.format,
            mediaType: encryptedPhoto.metadata.mediaType,
            duration: encryptedPhoto.metadata.duration,
            latitude: encryptedPhoto.metadata.latitude,
            longitude: encryptedPhoto.metadata.longitude,
            filePath: photoURL.path,
            thumbnailPath: thumbURL.path,
            albumId: albumId,
            tags: [],
            isFavorite: false,
            isHidden: false
        )

        try await PhotoStore.shared.add(photo)
    }

    /// Save a shared photo (from AirDrop)
    func saveSharedPhoto(_ photo: Photo, encryptedData: Data, thumbnail: Data? = nil) async throws {
        let photoDir = try photosSubdirectory
        let thumbDir = try thumbnailsSubdirectory

        // Create file URLs
        let photoURL = photoDir.appendingPathComponent("\(photo.id.uuidString).encrypted")
        let thumbURL = thumbDir.appendingPathComponent("\(photo.id.uuidString).thumb")

        // Write encrypted photo data
        try encryptedData.write(to: photoURL)

        // Write encrypted thumbnail if provided
        if let thumbnail = thumbnail {
            try thumbnail.write(to: thumbURL)
        }

        // Update photo with file paths
        var updatedPhoto = photo
        updatedPhoto.filePath = photoURL.path
        updatedPhoto.thumbnailPath = thumbnail != nil ? thumbURL.path : nil

        try await PhotoStore.shared.add(updatedPhoto)
    }

    // MARK: - Load Operations

    /// Load encrypted photo data
    func loadPhoto(for id: UUID) async throws -> Data {
        let photoDir = try photosSubdirectory
        let photoURL = photoDir.appendingPathComponent("\(id.uuidString).encrypted")

        guard fileManager.fileExists(atPath: photoURL.path) else {
            throw StorageError.photoNotFound
        }

        return try Data(contentsOf: photoURL)
    }

    /// Load encrypted thumbnail data
    func loadThumbnail(for id: UUID) async throws -> Data {
        let thumbDir = try thumbnailsSubdirectory
        let thumbURL = thumbDir.appendingPathComponent("\(id.uuidString).thumb")

        guard fileManager.fileExists(atPath: thumbURL.path) else {
            throw StorageError.thumbnailNotFound
        }

        return try Data(contentsOf: thumbURL)
    }

    /// Load all photos metadata
    func loadAllPhotos() async throws -> [Photo] {
        return await PhotoStore.shared.getAll()
    }

    // MARK: - Delete Operations

    /// Delete a photo and its thumbnail
    func deletePhoto(_ id: UUID) async throws {
        let photoDir = try photosSubdirectory
        let thumbDir = try thumbnailsSubdirectory

        let photoURL = photoDir.appendingPathComponent("\(id.uuidString).encrypted")
        let thumbURL = thumbDir.appendingPathComponent("\(id.uuidString).thumb")

        // Delete files
        try? fileManager.removeItem(at: photoURL)
        try? fileManager.removeItem(at: thumbURL)

        // Delete metadata
        await PhotoStore.shared.remove(id)
    }
}

// MARK: - Persistent Photo Store

actor PhotoStore {
    static let shared = PhotoStore()

    private var photos: [Photo] = []
    private let fileManager = FileManager.default

    /// Get the metadata file URL
    private var metadataURL: URL {
        get throws {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let locafotoDir = appSupport.appendingPathComponent("Locafoto")

            if !fileManager.fileExists(atPath: locafotoDir.path) {
                try fileManager.createDirectory(at: locafotoDir, withIntermediateDirectories: true)
            }

            return locafotoDir.appendingPathComponent("photos_metadata.json")
        }
    }

    func add(_ photo: Photo) async throws {
        // Remove existing if updating
        photos.removeAll { $0.id == photo.id }
        photos.append(photo)
        photos.sort { $0.captureDate > $1.captureDate }
        try saveMetadata()

        // Update album thumbnail
        let albumService = AlbumService.shared
        await albumService.updateAlbumThumbnails(albumId: photo.albumId)
    }

    func getAll() -> [Photo] {
        return photos
    }

    func get(_ id: UUID) -> Photo? {
        return photos.first { $0.id == id }
    }

    func remove(_ id: UUID) async {
        // Get album ID before removing
        let albumId = photos.first { $0.id == id }?.albumId

        photos.removeAll { $0.id == id }
        try? saveMetadata()

        // Update album thumbnail if we had an album
        if let albumId = albumId {
            let albumService = AlbumService.shared
            await albumService.updateAlbumThumbnails(albumId: albumId)
        }
    }

    /// Get photos for a specific album
    func getPhotos(forAlbum albumId: UUID) -> [Photo] {
        return photos.filter { $0.albumId == albumId }
    }

    /// Update a photo's album
    func updateAlbum(for photoId: UUID, to albumId: UUID) async {
        guard let index = photos.firstIndex(where: { $0.id == photoId }) else { return }

        let oldAlbumId = photos[index].albumId
        photos[index].albumId = albumId
        photos[index].modifiedDate = Date()
        try? saveMetadata()

        // Update thumbnails for both old and new albums
        let albumService = AlbumService.shared
        await albumService.updateAlbumThumbnails(albumIds: [oldAlbumId, albumId])
    }

    /// Load photos from disk on app launch
    func loadFromDisk() throws {
        let url = try metadataURL
        guard fileManager.fileExists(atPath: url.path) else {
            photos = []
            return
        }

        let data = try Data(contentsOf: url)
        photos = try JSONDecoder().decode([Photo].self, from: data)
        photos.sort { $0.captureDate > $1.captureDate }
    }

    /// Save photos metadata to disk
    private func saveMetadata() throws {
        let url = try metadataURL
        let data = try JSONEncoder().encode(photos)
        try data.write(to: url)
    }
}

// MARK: - Errors

enum StorageError: LocalizedError {
    case photoNotFound
    case thumbnailNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoNotFound:
            return "Photo not found"
        case .thumbnailNotFound:
            return "Thumbnail not found"
        case .saveFailed:
            return "Failed to save photo"
        }
    }
}
