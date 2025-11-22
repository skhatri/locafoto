import SwiftUI
import PhotosUI

@MainActor
class ImportViewModel: ObservableObject {
    @Published var showPhotoPicker = false
    @Published var showKeySelection = false
    @Published var showAlbumSelection = false
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importedCount = 0
    @Published var totalCount = 0
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?
    @Published var availableKeys: [KeyFile] = []
    @Published var availableAlbums: [Album] = []
    @Published var selectedKeyName: String?

    private let importService = PhotoImportService()
    private let keyManagementService = KeyManagementService()
    private let albumService = AlbumService.shared

    // Temporary storage for selected photos
    var pendingResults: [PHPickerResult] = []

    /// Load available keys
    func loadKeys() async {
        do {
            availableKeys = try await keyManagementService.loadAllKeys()
        } catch {
            print("Failed to load keys: \(error)")
            availableKeys = []
        }
    }

    /// Load available albums
    func loadAlbums() async {
        do {
            try await albumService.loadAlbums()
            availableAlbums = await albumService.getAllAlbums()
        } catch {
            print("Failed to load albums: \(error)")
            availableAlbums = []
        }
    }

    /// Called when photos are selected - shows key selection
    func onPhotosSelected(_ results: [PHPickerResult]) {
        pendingResults = results
        Task {
            await loadKeys()
            await loadAlbums()
            showKeySelection = true
        }
    }

    /// Import photos with selected key and album
    func importPhotos(keyName: String, albumId: UUID, pin: String) async {
        guard !pendingResults.isEmpty else { return }

        isImporting = true
        totalCount = pendingResults.count
        importedCount = 0
        importProgress = 0

        do {
            // Get the encryption key
            let encryptionKey = try await keyManagementService.getKey(byName: keyName, pin: pin)

            for (index, result) in pendingResults.enumerated() {
                try await importService.importPhoto(result, encryptionKey: encryptionKey, keyName: keyName, albumId: albumId)

                importedCount = index + 1
                importProgress = Double(importedCount) / Double(totalCount)
            }

            pendingResults = []
            isImporting = false
            showSuccessAlert = true

        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
            showErrorAlert = true
        }
    }
}
