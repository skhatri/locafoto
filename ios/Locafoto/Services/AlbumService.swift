import Foundation

/// Service for managing albums
actor AlbumService {
    static let shared = AlbumService()

    private let fileManager = FileManager.default
    private var albums: [Album] = []

    private init() {}

    /// Get the albums file URL
    private var albumsURL: URL {
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

            return locafotoDir.appendingPathComponent("albums.json")
        }
    }

    /// Load albums from disk
    func loadAlbums() throws {
        let url = try albumsURL
        guard fileManager.fileExists(atPath: url.path) else {
            albums = []
            return
        }

        let data = try Data(contentsOf: url)
        albums = try JSONDecoder().decode([Album].self, from: data)
        albums.sort { $0.modifiedDate > $1.modifiedDate }
    }

    /// Save albums to disk
    private func saveAlbums() throws {
        let url = try albumsURL
        let data = try JSONEncoder().encode(albums)
        try data.write(to: url)
    }

    /// Get all albums
    func getAllAlbums() -> [Album] {
        return albums
    }

    /// Get album by ID
    func getAlbum(_ id: UUID) -> Album? {
        return albums.first { $0.id == id }
    }

    /// Get the main album
    func getMainAlbum() -> Album? {
        return albums.first { $0.isMain }
    }

    /// Get albums using a specific key
    func getAlbums(forKey keyName: String) -> [Album] {
        return albums.filter { $0.keyName == keyName }
    }

    /// Create a new album
    func createAlbum(name: String, keyName: String, isMain: Bool = false) throws -> Album {
        // Load existing albums first to avoid overwriting
        try loadAlbums()

        let album = Album(name: name, keyName: keyName, isMain: isMain)
        albums.append(album)
        albums.sort { $0.modifiedDate > $1.modifiedDate }
        try saveAlbums()
        return album
    }

    /// Update album
    func updateAlbum(_ album: Album) throws {
        // Load existing albums first
        try loadAlbums()

        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            throw AlbumError.albumNotFound
        }

        var updatedAlbum = album
        updatedAlbum.modifiedDate = Date()
        albums[index] = updatedAlbum
        albums.sort { $0.modifiedDate > $1.modifiedDate }
        try saveAlbums()
    }

    /// Delete album
    func deleteAlbum(_ id: UUID) throws {
        // Load existing albums first
        try loadAlbums()

        guard albums.contains(where: { $0.id == id }) else {
            throw AlbumError.albumNotFound
        }

        albums.removeAll { $0.id == id }
        try saveAlbums()
    }

    /// Get default album for saving (first available album)
    func getDefaultAlbum() -> Album? {
        // Prefer album marked as main, otherwise return first album
        return albums.first { $0.isMain } ?? albums.first
    }

    /// Check if main album exists
    func hasMainAlbum() -> Bool {
        return albums.contains { $0.isMain }
    }

    /// Update album thumbnail cache based on current photos
    func updateAlbumThumbnails(albumId: UUID) async {
        // Load existing albums first
        try? loadAlbums()

        guard let index = albums.firstIndex(where: { $0.id == albumId }) else {
            return
        }

        // Get photos for this album sorted by date
        let photos = await PhotoStore.shared.getPhotos(forAlbum: albumId)
            .sorted { $0.captureDate < $1.captureDate }

        albums[index].photoCount = photos.count

        if photos.isEmpty {
            albums[index].firstPhotoId = nil
            albums[index].lastPhotoId = nil
        } else if photos.count == 1 {
            albums[index].firstPhotoId = photos.first?.id
            albums[index].lastPhotoId = nil
        } else {
            albums[index].firstPhotoId = photos.first?.id
            albums[index].lastPhotoId = photos.last?.id
        }

        albums[index].modifiedDate = Date()
        try? saveAlbums()
    }

    /// Update thumbnails for multiple albums
    func updateAlbumThumbnails(albumIds: [UUID]) async {
        for albumId in albumIds {
            await updateAlbumThumbnails(albumId: albumId)
        }
    }

    /// Refresh all album thumbnails
    func refreshAllAlbumThumbnails() async {
        for album in albums {
            await updateAlbumThumbnails(albumId: album.id)
        }
    }
}

// MARK: - Errors

enum AlbumError: LocalizedError {
    case albumNotFound
    case noAlbumAvailable

    var errorDescription: String? {
        switch self {
        case .albumNotFound:
            return "Album not found"
        case .noAlbumAvailable:
            return "No album available. Please create an album first."
        }
    }
}
