import SwiftUI

@MainActor
class GalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false

    private let storageService = StorageService()
    private let trackingService = LFSFileTrackingService()
    private let albumService = AlbumService.shared

    /// Load all photos from storage, excluding photos from private albums
    func loadPhotos() async {
        isLoading = true

        do {
            // Load all photos
            let allPhotos = try await storageService.loadAllPhotos()

            // Load albums to identify private ones
            try await albumService.loadAlbums()
            let albums = await albumService.getAllAlbums()

            // Get IDs of private albums
            let privateAlbumIds = Set(albums.filter { $0.isPrivate }.map { $0.id })

            // Filter out photos from private albums
            var filteredPhotos = allPhotos.filter { !privateAlbumIds.contains($0.albumId) }

            // Apply sorting based on user preference
            filteredPhotos = sortPhotos(filteredPhotos)

            photos = filteredPhotos
        } catch {
            print("Failed to load photos: \(error)")
            photos = []
        }

        isLoading = false
    }

    /// Sort photos based on user preference
    private func sortPhotos(_ photos: [Photo]) -> [Photo] {
        let sortOptionRaw = UserDefaults.standard.string(forKey: "photoSortOption") ?? PhotoSortOption.captureDateDesc.rawValue
        let sortOption = PhotoSortOption(rawValue: sortOptionRaw) ?? .captureDateDesc

        switch sortOption {
        case .captureDateDesc:
            return photos.sorted { $0.captureDate > $1.captureDate }
        case .captureDateAsc:
            return photos.sorted { $0.captureDate < $1.captureDate }
        case .importDateDesc:
            return photos.sorted { $0.importDate > $1.importDate }
        case .importDateAsc:
            return photos.sorted { $0.importDate < $1.importDate }
        case .sizeDesc:
            return photos.sorted { $0.originalSize > $1.originalSize }
        case .sizeAsc:
            return photos.sorted { $0.originalSize < $1.originalSize }
        }
    }

    /// Re-apply sorting to current photos
    func applySorting() {
        photos = sortPhotos(photos)
    }

    /// Delete a photo and its LFS tracking
    func deletePhoto(_ photo: Photo) async {
        do {
            // Delete LFS tracking
            try await trackingService.deleteTracking(byPhotoId: photo.id)
            // Delete storage files
            try await storageService.deletePhoto(photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            print("Failed to delete photo: \(error)")
        }
    }
}
