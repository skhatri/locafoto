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

    /// Get the photos subdirectory
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
    func savePhoto(_ encryptedPhoto: EncryptedPhoto, thumbnail: Data) async throws {
        let photoDir = try photosSubdirectory
        let thumbDir = try thumbnailsSubdirectory

        // Create file URLs
        let photoURL = photoDir.appendingPathComponent("\(encryptedPhoto.id.uuidString).encrypted")
        let thumbURL = thumbDir.appendingPathComponent("\(encryptedPhoto.id.uuidString).thumb")

        // Write encrypted photo data
        try encryptedPhoto.encryptedData.write(to: photoURL)

        // Write encrypted thumbnail
        try thumbnail.write(to: thumbURL)

        // Save metadata to in-memory store (would be CoreData in production)
        let photo = Photo(
            id: encryptedPhoto.id,
            encryptedKeyData: encryptedPhoto.encryptedKey,
            ivData: encryptedPhoto.iv,
            authTagData: encryptedPhoto.authTag,
            captureDate: encryptedPhoto.metadata.captureDate,
            importDate: Date(),
            modifiedDate: Date(),
            originalSize: Int64(encryptedPhoto.metadata.originalSize),
            encryptedSize: Int64(encryptedPhoto.encryptedData.count),
            width: encryptedPhoto.metadata.width.map { Int32($0) },
            height: encryptedPhoto.metadata.height.map { Int32($0) },
            format: encryptedPhoto.metadata.format,
            filePath: photoURL.path,
            thumbnailPath: thumbURL.path,
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

// MARK: - In-Memory Photo Store (Replace with CoreData in production)

actor PhotoStore {
    static let shared = PhotoStore()

    private var photos: [Photo] = []

    func add(_ photo: Photo) throws {
        // Remove existing if updating
        photos.removeAll { $0.id == photo.id }
        photos.append(photo)
        photos.sort { $0.captureDate > $1.captureDate }
    }

    func getAll() -> [Photo] {
        return photos
    }

    func get(_ id: UUID) -> Photo? {
        return photos.first { $0.id == id }
    }

    func remove(_ id: UUID) {
        photos.removeAll { $0.id == id }
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
