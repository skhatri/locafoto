import SwiftUI

@MainActor
class AlbumViewModel: ObservableObject {
    @Published var albums: [Album] = []
    @Published var isLoading = false
    @Published var availableKeys: [KeyFile] = []

    private let albumService = AlbumService()
    private let keyManagementService = KeyManagementService()

    /// Load all albums
    func loadAlbums() async {
        isLoading = true

        do {
            try await albumService.loadAlbums()
            albums = await albumService.getAllAlbums()
        } catch {
            print("Failed to load albums: \(error)")
            albums = []
        }

        isLoading = false
    }

    /// Load available keys
    func loadKeys() async {
        do {
            availableKeys = try await keyManagementService.loadAllKeys()
        } catch {
            print("Failed to load keys: \(error)")
            availableKeys = []
        }
    }

    /// Create a new album
    func createAlbum(name: String, keyName: String) async -> Album? {
        do {
            let album = try await albumService.createAlbum(name: name, keyName: keyName)
            albums = await albumService.getAllAlbums()
            return album
        } catch {
            print("Failed to create album: \(error)")
            return nil
        }
    }

    /// Delete an album
    func deleteAlbum(_ album: Album) async {
        do {
            try await albumService.deleteAlbum(album.id)
            albums.removeAll { $0.id == album.id }
        } catch {
            print("Failed to delete album: \(error)")
        }
    }

    /// Get photo count for album
    func getPhotoCount(for album: Album) async -> Int {
        return await PhotoStore.shared.getPhotos(forAlbum: album.id).count
    }
}
