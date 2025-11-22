import SwiftUI

@MainActor
class GalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false

    private let storageService = StorageService()
    private let trackingService = LFSFileTrackingService()

    /// Load all photos from storage
    func loadPhotos() async {
        isLoading = true

        do {
            photos = try await storageService.loadAllPhotos()
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
