import SwiftUI

@MainActor
class KeyLibraryViewModel: ObservableObject {
    @Published var keys: [KeyFile] = []
    @Published var isLoading = false
    @Published var fileCounts: [String: Int] = [:]
    @Published var totalFilesEncrypted = 0

    private let keyManagementService = KeyManagementService()
    private let trackingService = LFSFileTrackingService()

    func loadKeys() async {
        isLoading = true

        do {
            keys = try await keyManagementService.loadAllKeys()

            // Load file counts for each key
            var counts: [String: Int] = [:]
            var total = 0

            for key in keys {
                let count = try await trackingService.getUsageCount(forKey: key.name)
                counts[key.name] = count
                total += count
            }

            fileCounts = counts
            totalFilesEncrypted = total
        } catch {
            print("Failed to load keys: \(error)")
            keys = []
            fileCounts = [:]
            totalFilesEncrypted = 0
        }

        isLoading = false
    }

    func createKey(name: String, pin: String) async {
        do {
            let keyFile = try await keyManagementService.createKey(name: name, pin: pin)
            keys.insert(keyFile, at: 0)
            fileCounts[keyFile.name] = 0
        } catch {
            print("Failed to create key: \(error)")
        }
    }

    func importKey(name: String, keyData: Data, pin: String) async {
        do {
            let keyFile = try await keyManagementService.importKey(name: name, keyData: keyData, pin: pin)
            keys.insert(keyFile, at: 0)
            fileCounts[keyFile.name] = 0
        } catch {
            print("Failed to import key: \(error)")
        }
    }

    func checkCanDelete(_ key: KeyFile) async {
        // Reload file counts to ensure we have latest
        do {
            let count = try await trackingService.getUsageCount(forKey: key.name)
            fileCounts[key.name] = count
        } catch {
            print("Failed to check key usage: \(error)")
        }
    }

    func canDeleteKey(_ key: KeyFile) -> Bool {
        return fileCount(for: key.name) == 0
    }

    func fileCount(for keyName: String) -> Int {
        return fileCounts[keyName] ?? 0
    }

    func deleteKey(_ id: UUID) async {
        guard let key = keys.first(where: { $0.id == id }) else { return }

        // Check if key is in use
        if !canDeleteKey(key) {
            print("Cannot delete key - still in use")
            return
        }

        do {
            try await keyManagementService.deleteKey(id)
            keys.removeAll { $0.id == id }
            fileCounts.removeValue(forKey: key.name)
        } catch {
            print("Failed to delete key: \(error)")
        }
    }
}
