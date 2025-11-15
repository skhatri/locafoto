import SwiftUI

@MainActor
class KeyLibraryViewModel: ObservableObject {
    @Published var keys: [KeyFile] = []
    @Published var isLoading = false

    private let keyManagementService = KeyManagementService()

    func loadKeys() async {
        isLoading = true

        do {
            keys = try await keyManagementService.loadAllKeys()
        } catch {
            print("Failed to load keys: \(error)")
            keys = []
        }

        isLoading = false
    }

    func createKey(name: String, pin: String) async {
        do {
            let keyFile = try await keyManagementService.createKey(name: name, pin: pin)
            keys.insert(keyFile, at: 0)
        } catch {
            print("Failed to create key: \(error)")
        }
    }

    func importKey(name: String, keyData: Data, pin: String) async {
        do {
            let keyFile = try await keyManagementService.importKey(name: name, keyData: keyData, pin: pin)
            keys.insert(keyFile, at: 0)
        } catch {
            print("Failed to import key: \(error)")
        }
    }

    func deleteKey(_ id: UUID) async {
        do {
            try await keyManagementService.deleteKey(id)
            keys.removeAll { $0.id == id }
        } catch {
            print("Failed to delete key: \(error)")
        }
    }
}
