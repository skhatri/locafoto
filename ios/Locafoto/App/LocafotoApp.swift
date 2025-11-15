import SwiftUI

@main
struct LocafotoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    Task {
                        await handleIncomingShare(url: url)
                    }
                }
        }
    }

    /// Handle incoming .locaphoto files from AirDrop
    private func handleIncomingShare(url: URL) async {
        guard url.pathExtension == "locaphoto" else {
            print("Invalid file type received")
            return
        }

        do {
            let sharingService = SharingService()
            let photo = try await sharingService.handleIncomingShare(from: url)
            print("Successfully imported shared photo: \(photo.id)")
            // Notify app state to refresh gallery
            await MainActor.run {
                appState.shouldRefreshGallery = true
            }
        } catch {
            print("Failed to import shared photo: \(error)")
        }
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var shouldRefreshGallery = false
    @Published var selectedTab = 0
}
