import SwiftUI

@MainActor
class GalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false

    private let storageService = StorageService()

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

    /// Delete a photo
    func deletePhoto(_ photo: Photo) async {
        do {
            try await storageService.deletePhoto(photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            print("Failed to delete photo: \(error)")
        }
    }
}
