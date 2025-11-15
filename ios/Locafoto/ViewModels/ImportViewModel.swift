import SwiftUI
import PhotosUI

@MainActor
class ImportViewModel: ObservableObject {
    @Published var showPhotoPicker = false
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importedCount = 0
    @Published var totalCount = 0
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    private let importService = PhotoImportService()

    /// Import photos from PHPickerResults
    func importPhotos(_ results: [PHPickerResult]) async {
        guard !results.isEmpty else { return }

        isImporting = true
        totalCount = results.count
        importedCount = 0
        importProgress = 0

        do {
            for (index, result) in results.enumerated() {
                try await importService.importPhoto(result)

                importedCount = index + 1
                importProgress = Double(importedCount) / Double(totalCount)
            }

            isImporting = false
            showSuccessAlert = true

        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
            showErrorAlert = true
        }
    }
}
