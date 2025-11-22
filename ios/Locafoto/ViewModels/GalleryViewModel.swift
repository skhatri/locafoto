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
            photos = allPhotos.filter { !privateAlbumIds.contains($0.albumId) }
        } catch {
            print("Failed to load photos: \(error)")
            photos = []
        }

        isLoading = false
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
