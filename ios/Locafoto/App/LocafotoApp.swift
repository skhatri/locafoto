import SwiftUI

@main
struct LocafotoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    Task {
                        await handleIncomingShare(url: url)
                    }
                }
                .onAppear {
                    Task {
                        await appState.checkPinStatus()
                    }
                }
        }
    }

    /// Handle incoming .locaphoto and .lfs files from AirDrop
    private func handleIncomingShare(url: URL) async {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "locaphoto":
            await handleLocaphotoFile(url: url)
        case "lfs":
            await handleLFSFile(url: url)
        default:
            print("Unsupported file type: \(ext)")
        }
    }

    private func handleLocaphotoFile(url: URL) async {
        do {
            let sharingService = SharingService()
            let photo = try await sharingService.handleIncomingShare(from: url)
            print("✅ Successfully imported .locaphoto: \(photo.id)")
            await MainActor.run {
                appState.shouldRefreshGallery = true
            }
        } catch {
            print("❌ Failed to import .locaphoto: \(error)")
        }
    }

    private func handleLFSFile(url: URL) async {
        // Wait for PIN to be available
        await appState.waitForUnlock()

        guard let pin = await appState.currentPin else {
            print("❌ No PIN available to decrypt .lfs file")
            return
        }

        do {
            let lfsService = LFSImportService()
            let photo = try await lfsService.handleIncomingLFSFile(from: url, pin: pin)
            print("✅ Successfully imported .lfs file: \(photo.id)")
            await MainActor.run {
                appState.shouldRefreshGallery = true
            }
        } catch {
            print("❌ Failed to import .lfs file: \(error)")
            await MainActor.run {
                appState.lfsImportError = error.localizedDescription
            }
        }
    }
}

/// Root view that shows PIN setup/unlock or main content
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isPinChecked {
                // Loading state
                ProgressView("Loading...")
            } else if !appState.isPinSet {
                // First launch - set up PIN
                PINSetupView { pin in
                    await appState.setupPIN(pin)
                }
            } else if !appState.isUnlocked {
                // App is locked - need to unlock
                PINUnlockView { pin in
                    return await appState.unlock(with: pin)
                }
            } else {
                // Unlocked - show main app
                ContentView()
            }
        }
        .alert("LFS Import Error", isPresented: .constant(appState.lfsImportError != nil)) {
            Button("OK") {
                appState.lfsImportError = nil
            }
        } message: {
            if let error = appState.lfsImportError {
                Text(error)
            }
        }
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var shouldRefreshGallery = false
    @Published var selectedTab = 0
    @Published var isPinChecked = false
    @Published var isPinSet = false
    @Published var isUnlocked = false
    @Published var lfsImportError: String?

    var currentPin: String?

    private let keyManagementService = KeyManagementService()

    /// Check if PIN is already set up
    func checkPinStatus() async {
        let pinSet = await keyManagementService.isPinSet()
        isPinSet = pinSet
        isPinChecked = true

        // If PIN not set, user needs to set it up first
        // If PIN is set, user needs to unlock
    }

    /// Set up PIN for first time
    func setupPIN(_ pin: String) async {
        do {
            try await keyManagementService.initializeMasterKey(pin: pin)
            currentPin = pin
            isPinSet = true
            isUnlocked = true
        } catch {
            print("Failed to set up PIN: \(error)")
        }
    }

    /// Unlock app with PIN
    func unlock(with pin: String) async -> Bool {
        do {
            let valid = try await keyManagementService.verifyPin(pin)
            if valid {
                currentPin = pin
                isUnlocked = true
                return true
            }
            return false
        } catch {
            print("Failed to verify PIN: \(error)")
            return false
        }
    }

    /// Lock the app
    func lock() {
        currentPin = nil
        isUnlocked = false
    }

    /// Wait for app to be unlocked (for background imports)
    func waitForUnlock() async {
        while !isUnlocked {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
}
