import SwiftUI

@MainActor
class LFSLibraryViewModel: ObservableObject {
    @Published var files: [LFSImportedFile] = []
    @Published var statistics = LFSStatistics(totalFiles: 0, totalSize: 0, uniqueKeys: 0)
    @Published var isLoading = false

    private let trackingService = LFSFileTrackingService()
    private let storageService = StorageService()

    func loadFiles() async {
        isLoading = true

        do {
            files = try await trackingService.getAllImports()
            statistics = try await trackingService.getStatistics()
        } catch {
            print("Failed to load LFS files: \(error)")
            files = []
            statistics = LFSStatistics(totalFiles: 0, totalSize: 0, uniqueKeys: 0)
        }

        isLoading = false
    }

    func deleteFile(_ file: LFSImportedFile) async {
        do {
            // Delete the photo from storage
            try await storageService.deletePhoto(file.photoId)

            // Delete tracking
            try await trackingService.deleteTracking(fileId: file.id)

            // Reload
            await loadFiles()
        } catch {
            print("Failed to delete file: \(error)")
        }
    }
}
