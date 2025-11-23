import SwiftUI

@MainActor
class AlbumViewModel: ObservableObject {
    @Published var albums: [Album] = []
    @Published var isLoading = false
    @Published var availableKeys: [KeyFile] = []

    private let albumService = AlbumService.shared
    private let keyManagementService = KeyManagementService()

    /// Load all albums and apply sorting
    func loadAlbums() async {
        isLoading = true

        do {
            try await albumService.loadAlbums()
            var loadedAlbums = await albumService.getAllAlbums()

            // Apply sorting based on user preference
            let sortOptionRaw = UserDefaults.standard.string(forKey: "albumSortOption") ?? AlbumSortOption.modifiedDateDesc.rawValue
            let sortOption = AlbumSortOption(rawValue: sortOptionRaw) ?? .modifiedDateDesc
            loadedAlbums = sortAlbums(loadedAlbums, by: sortOption)

            albums = loadedAlbums
        } catch {
            print("Failed to load albums: \(error)")
            albums = []
        }

        isLoading = false
    }

    /// Sort albums by the specified option
    func sortAlbums(_ albums: [Album], by option: AlbumSortOption) -> [Album] {
        switch option {
        case .modifiedDateDesc:
            return albums.sorted { $0.modifiedDate > $1.modifiedDate }
        case .modifiedDateAsc:
            return albums.sorted { $0.modifiedDate < $1.modifiedDate }
        case .createdDateDesc:
            return albums.sorted { $0.createdDate > $1.createdDate }
        case .createdDateAsc:
            return albums.sorted { $0.createdDate < $1.createdDate }
        case .nameAsc:
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .photoCountDesc:
            return albums.sorted { $0.photoCount > $1.photoCount }
        case .photoCountAsc:
            return albums.sorted { $0.photoCount < $1.photoCount }
        }
    }

    /// Apply current sort preference to albums
    func applySorting() {
        let sortOptionRaw = UserDefaults.standard.string(forKey: "albumSortOption") ?? AlbumSortOption.modifiedDateDesc.rawValue
        let sortOption = AlbumSortOption(rawValue: sortOptionRaw) ?? .modifiedDateDesc
        albums = sortAlbums(albums, by: sortOption)
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
