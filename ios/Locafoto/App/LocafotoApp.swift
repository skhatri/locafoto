import SwiftUI

@main
struct LocafotoApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Clear keychain on fresh install (app deleted but keychain persisted)
        KeyManagementService.checkAndClearKeychainOnFreshInstall()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    print("🔵 onOpenURL CALLED with: \(url)")
                    print("🔵 URL path: \(url.path)")
                    print("🔵 URL scheme: \(url.scheme ?? "nil")")
                    Task {
                        await handleIncomingShare(url: url)
                    }
                }
                .onAppear {
                    Task {
                        await appState.checkPinStatus()
                        // CRITICAL: Check Inbox directory for files iOS may have saved before calling onOpenURL
                        await checkInboxDirectory()
                    }
                }
        }
    }
    
    /// Check the app's Inbox directory for files that iOS saved before calling onOpenURL
    private func checkInboxDirectory() async {
        let fileManager = FileManager.default
        
        // Get the app's Documents directory
        guard let documentsDir = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return
        }
        
        let inboxDir = documentsDir.appendingPathComponent("Inbox")
        
        guard fileManager.fileExists(atPath: inboxDir.path) else {
            print("ℹ️ No Inbox directory found")
            return
        }
        
        do {
            let inboxFiles = try fileManager.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)
            
            if !inboxFiles.isEmpty {
                print("⚠️ Found \(inboxFiles.count) file(s) in Inbox directory - iOS saved them before calling onOpenURL")
                for file in inboxFiles {
                    print("📦 Inbox file: \(file.lastPathComponent)")
                    // Process each file
                    await handleIncomingShare(url: file)
                }
            }
        } catch {
            print("❌ Failed to check Inbox directory: \(error)")
        }
    }

    /// Handle incoming files from AirDrop when app is opened via UTI match
    /// 
    /// Flow:
    /// 1. File is read IMMEDIATELY while we have security-scoped access (prevents iOS from saving to Files app)
    /// 2. File is saved to temp location (persists even if app is locked)
    /// 3. Original AirDrop file is deleted immediately (prevents Files app visibility)
    /// 4. If app is already unlocked: Process immediately (no PIN prompt)
    /// 5. If app is locked: Wait for user to unlock, then process immediately
    /// 
    /// File types:
    /// - .lfkey files: Saved as key immediately (after unlock if needed)
    /// - .lfs files: Saved to default gallery (main album) immediately (after unlock if needed)
    /// - .locaphoto files: Imported to main album
    private func handleIncomingShare(url: URL) async {
        print("═══════════════════════════════════════")
        print("📥 HANDLE INCOMING SHARE CALLED")
        print("📥 File: \(url.lastPathComponent)")
        print("📥 Full path: \(url.path)")
        print("📥 Is file accessible: \(FileManager.default.fileExists(atPath: url.path))")
        
        // CRITICAL: Access security-scoped resource immediately
        // This prevents iOS from saving the file to Files app
        let hasAccess = url.startAccessingSecurityScopedResource()
        print("📥 Security-scoped access granted: \(hasAccess)")
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check if file is in app's Inbox or Documents directory
        let isInInbox = url.path.contains("/Inbox/")
        let isInDocuments = url.path.contains("/Documents/")
        let isInFilesApp = isInInbox || isInDocuments
        
        if isInInbox {
            print("⚠️ CRITICAL: File is in Inbox directory - iOS saved it here!")
            print("⚠️ This file is VISIBLE in Files app - must delete IMMEDIATELY")
        }
        if isInDocuments {
            print("⚠️ File is in Documents directory")
        }
        
        // CRITICAL: If file is in Inbox, we MUST read and delete it immediately
        // before iOS makes it visible in Files app
        let ext = url.pathExtension.lowercased()
        print("📄 File extension: \(ext)")
        print("═══════════════════════════════════════")

        switch ext {
        case "locaphoto":
            await handleLocaphotoFile(url: url, isInFilesApp: isInFilesApp)
        case "lfs":
            await handleLFSFile(url: url, isInFilesApp: isInFilesApp)
        case "lfkey":
            await handleKeyFile(url: url, isInFilesApp: isInFilesApp)
        default:
            print("❌ Unsupported file type: \(ext)")
        }
    }

    private func handleLocaphotoFile(url: URL, isInFilesApp: Bool) async {
        do {
            // Read file data immediately while we have access
            let fileData = try Data(contentsOf: url)
            
            // Copy to a temporary location we control
            let tempURL = try copyToTempLocation(data: fileData, filename: url.lastPathComponent)
            
            // If file was in Files app, delete it immediately to prevent user from seeing it there
            if isInFilesApp {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("🗑️ Removed file from Files app directory")
                } catch {
                    print("⚠️ Could not remove file from Files app: \(error)")
                }
            } else {
                // Clean up the original AirDrop file immediately
                try? FileManager.default.removeItem(at: url)
            }
            
            let sharingService = SharingService()
            let photo = try await sharingService.handleIncomingShare(from: tempURL)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Successfully imported .locaphoto: \(photo.id)")
            await MainActor.run {
                appState.shouldRefreshGallery = true
            }
        } catch {
            print("❌ Failed to import .locaphoto: \(error)")
        }
    }

    private func handleLFSFile(url: URL, isInFilesApp: Bool) async {
        // Increment pending count
        await MainActor.run {
            appState.pendingImportCount += 1
        }

        // CRITICAL: Read file data IMMEDIATELY while we have security-scoped access
        // Don't wait for unlock - the file might become inaccessible
        let tempURL: URL
        do {
            // Read file data immediately while we have access
            let fileData = try Data(contentsOf: url)
            
            // Copy to a temporary location we control (this persists across unlock)
            tempURL = try copyToTempLocation(data: fileData, filename: url.lastPathComponent)
            
            // Save a copy to our received files directory for reference
            try saveReceivedFile(data: fileData, filename: url.lastPathComponent, type: "lfs")
            
            // If file was in Files app, delete it immediately to prevent user from seeing it there
            if isInFilesApp {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("🗑️ Removed .lfs file from Files app directory")
                } catch {
                    print("⚠️ Could not remove file from Files app: \(error)")
                }
            } else {
                // Clean up the original AirDrop file immediately to prevent saving to Files app
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            print("❌ Failed to read .lfs file: \(error)")
            await MainActor.run {
                appState.lfsImportError = "Failed to read file: \(error.localizedDescription)"
                appState.pendingImportCount -= 1
            }
            return
        }

        // NOW wait for PIN unlock (returns immediately if app is already unlocked)
        // File is safely saved to temp location, so we can wait if needed
        await appState.waitForUnlock()

        guard let pin = await appState.currentPin else {
            print("❌ No PIN available to decrypt .lfs file - will process on next unlock")
            // Don't delete temp file - it will be processed on next unlock
            await MainActor.run {
                appState.pendingImportCount -= 1
            }
            return
        }

        do {
            // Process the file from temp location - save to default gallery immediately
            let lfsService = LFSImportService()
            let photo = try await lfsService.handleIncomingLFSFile(from: tempURL, pin: pin)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Successfully imported .lfs file to gallery: \(photo.id)")
            await MainActor.run {
                appState.shouldRefreshGallery = true
                appState.pendingImportCount -= 1
            }
        } catch {
            print("❌ Failed to import .lfs file: \(error)")
            await MainActor.run {
                appState.lfsImportError = error.localizedDescription
                appState.pendingImportCount -= 1
            }
        }
    }

    private func handleKeyFile(url: URL, isInFilesApp: Bool) async {
        // CRITICAL: Read file data IMMEDIATELY while we have security-scoped access
        // Don't wait for unlock - the file might become inaccessible
        let tempURL: URL
        let sharedKey: SharedKeyFile
        
        do {
            // Read the key file immediately while we have access
            let fileData = try Data(contentsOf: url)
            
            // Copy to a temporary location we control (this persists across unlock)
            tempURL = try copyToTempLocation(data: fileData, filename: url.lastPathComponent)
            
            // Save a copy to our received files directory for reference
            try saveReceivedFile(data: fileData, filename: url.lastPathComponent, type: "keys")
            
            // If file was in Files app, delete it immediately to prevent user from seeing it there
            if isInFilesApp {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("🗑️ Removed .lfkey file from Files app directory")
                } catch {
                    print("⚠️ Could not remove file from Files app: \(error)")
                }
            } else {
                // Clean up the original AirDrop file immediately to prevent saving to Files app
                try? FileManager.default.removeItem(at: url)
            }

            // Decode the shared key structure immediately (no PIN needed for this)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sharedKey = try decoder.decode(SharedKeyFile.self, from: fileData)
            
            print("🔑 Parsed key file: '\(sharedKey.name)'")
        } catch {
            print("❌ Failed to read/parse .lfkey file: \(error)")
            await MainActor.run {
                appState.lfsImportError = "Failed to read key file: \(error.localizedDescription)"
            }
            return
        }

        // NOW wait for PIN unlock (returns immediately if app is already unlocked)
        // File is safely saved and parsed, so we can wait if needed
        await appState.waitForUnlock()

        guard let pin = await appState.currentPin else {
            print("❌ No PIN available to import key file")
            // Don't delete temp file - it will be processed on next unlock
            return
        }

        do {
            // Import the key immediately - no review needed, just save it
            let keyManagementService = KeyManagementService()
            _ = try await keyManagementService.importKey(
                name: sharedKey.name,
                keyData: sharedKey.keyData,
                pin: pin
            )

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            print("✅ Successfully imported key: \(sharedKey.name)")

            // Notify UI to refresh keys and show success
            await MainActor.run {
                appState.shouldRefreshKeys = true
                appState.keyImportSuccess = sharedKey.name
            }
        } catch {
            print("❌ Failed to import key: \(error)")
            await MainActor.run {
                appState.lfsImportError = "Failed to import key: \(error.localizedDescription)"
            }
        }
    }
    
    /// Copy file data to a temporary location we control
    private func copyToTempLocation(data: Data, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let appTempDir = tempDir.appendingPathComponent("Locafoto/Incoming")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appTempDir, withIntermediateDirectories: true)
        
        let tempURL = appTempDir.appendingPathComponent(filename)
        try data.write(to: tempURL)
        
        return tempURL
    }

    /// Save received file to app storage for later access
    private func saveReceivedFile(data: Data, filename: String, type: String) throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let receivedDir = appSupport.appendingPathComponent("Locafoto/Received/\(type)")

        if !fileManager.fileExists(atPath: receivedDir.path) {
            try fileManager.createDirectory(at: receivedDir, withIntermediateDirectories: true)
        }

        // Use unique filename if already exists
        var targetURL = receivedDir.appendingPathComponent(filename)
        var counter = 1
        while fileManager.fileExists(atPath: targetURL.path) {
            let name = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            targetURL = receivedDir.appendingPathComponent("\(name)_\(counter).\(ext)")
            counter += 1
        }

        try data.write(to: targetURL)
        print("📁 Saved received file to: \(targetURL.path)")
    }
}

/// Structure for shared key files (.lfkey)
struct SharedKeyFile: Codable {
    let name: String
    let keyData: Data
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
            } else if appState.needsMainAlbumSetup {
                // Need to set up main album
                MainAlbumSetupView()
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
        .alert("Key Imported", isPresented: .constant(appState.keyImportSuccess != nil)) {
            Button("OK") {
                appState.keyImportSuccess = nil
            }
        } message: {
            if let keyName = appState.keyImportSuccess {
                Text("Successfully imported key: \(keyName)")
            }
        }
    }
}

/// View to set up the main album on first launch
struct MainAlbumSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var keys: [KeyFile] = []
    @State private var selectedKeyName: String?
    @State private var showCreateKey = false
    @State private var newKeyName = ""

    private let keyManagementService = KeyManagementService()

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.locafotoPrimary)

                Text("Set Up Main Album")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Every photo needs to belong to an album. Select or create a key for your Main album.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if keys.isEmpty {
                    VStack(spacing: 16) {
                        Text("No keys available")
                            .foregroundColor(.secondary)

                        Button("Create Key") {
                            showCreateKey = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section(header: Text("Select Key for Main Album")) {
                            ForEach(keys) { key in
                                Button(action: {
                                    selectedKeyName = key.name
                                }) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.blue)
                                        Text(key.name)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedKeyName == key.name {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)

                    Button("Continue") {
                        if let keyName = selectedKeyName {
                            Task {
                                await appState.createMainAlbum(keyName: keyName)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedKeyName == nil)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateKey = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateKey) {
                CreateKeyForMainAlbumView { keyName in
                    showCreateKey = false
                    selectedKeyName = keyName
                    Task {
                        await loadKeys()
                    }
                }
            }
            .onAppear {
                Task {
                    await loadKeys()
                }
            }
        }
    }

    private func loadKeys() async {
        do {
            keys = try await keyManagementService.loadAllKeys()
            if selectedKeyName == nil {
                selectedKeyName = keys.first?.name
            }
        } catch {
            print("Failed to load keys: \(error)")
        }
    }
}

/// Simple view to create a key for main album setup
struct CreateKeyForMainAlbumView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var keyName = "Main"
    @State private var isCreating = false

    let onCreated: (String) -> Void

    private let keyManagementService = KeyManagementService()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Name")) {
                    TextField("Key Name", text: $keyName)
                }

                Section(footer: Text("A secure random key will be generated automatically.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Create Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createKey()
                        }
                    }
                    .disabled(keyName.isEmpty || isCreating)
                }
            }
        }
    }

    private func createKey() async {
        guard let pin = appState.currentPin else { return }
        isCreating = true

        do {
            _ = try await keyManagementService.createKey(name: keyName, pin: pin)
            onCreated(keyName)
        } catch {
            print("Failed to create key: \(error)")
        }

        isCreating = false
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var shouldRefreshGallery = false
    @Published var shouldRefreshKeys = false
    @Published var selectedTab = 0
    @Published var isPinChecked = false
    @Published var isPinSet = false
    @Published var isUnlocked = false
    @Published var needsMainAlbumSetup = false
    @Published var lfsImportError: String?
    @Published var keyImportSuccess: String?
    @Published var pendingImportCount: Int = 0

    var currentPin: String?

    private let keyManagementService = KeyManagementService()
    private let albumService = AlbumService()
    private let seedDataService = SeedDataService()

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

            // Load seed data on first install
            await seedDataService.loadSeedDataIfNeeded()
            shouldRefreshGallery = true
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

                // Load saved photos from disk
                try? await PhotoStore.shared.loadFromDisk()

                // Load albums and check for main album
                try? await albumService.loadAlbums()
                let hasMain = await albumService.hasMainAlbum()
                if !hasMain {
                    needsMainAlbumSetup = true
                }

                shouldRefreshGallery = true

                // CRITICAL: Check for pending temp files that need processing
                Task {
                    await processPendingTempFiles(pin: pin)
                }

                return true
            }
            return false
        } catch {
            print("Failed to verify PIN: \(error)")
            return false
        }
    }
    
    /// Process any pending temp files that were saved while app was locked
    private func processPendingTempFiles(pin: String) async {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let appTempDir = tempDir.appendingPathComponent("Locafoto/Incoming")
        
        guard fileManager.fileExists(atPath: appTempDir.path) else {
            return // No temp directory, nothing to process
        }
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: appTempDir, includingPropertiesForKeys: nil)
            
            for tempURL in tempFiles {
                let ext = tempURL.pathExtension.lowercased()
                print("🔄 Processing pending temp file: \(tempURL.lastPathComponent)")
                
                switch ext {
                case "lfs":
                    await processPendingLFSFile(tempURL: tempURL, pin: pin)
                case "lfkey":
                    await processPendingKeyFile(tempURL: tempURL, pin: pin)
                case "locaphoto":
                    await processPendingLocaphotoFile(tempURL: tempURL)
                default:
                    // Unknown file type, clean it up
                    try? fileManager.removeItem(at: tempURL)
                }
            }
        } catch {
            print("⚠️ Failed to check for pending temp files: \(error)")
        }
    }
    
    /// Process a pending .lfs file from temp location
    private func processPendingLFSFile(tempURL: URL, pin: String) async {
        // Check if file still exists (might have been processed by handler)
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            print("ℹ️ Temp .lfs file already processed: \(tempURL.lastPathComponent)")
            return
        }
        
        do {
            let lfsService = LFSImportService()
            let photo = try await lfsService.handleIncomingLFSFile(from: tempURL, pin: pin)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Processed pending .lfs file: \(photo.id)")
            await MainActor.run {
                shouldRefreshGallery = true
            }
        } catch {
            print("❌ Failed to process pending .lfs file: \(error)")
            // Keep the file for retry on next unlock
        }
    }
    
    /// Process a pending .lfkey file from temp location
    private func processPendingKeyFile(tempURL: URL, pin: String) async {
        // Check if file still exists (might have been processed by handler)
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            print("ℹ️ Temp .lfkey file already processed: \(tempURL.lastPathComponent)")
            return
        }
        
        do {
            let fileData = try Data(contentsOf: tempURL)
            
            // Decode the shared key structure
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sharedKey = try decoder.decode(SharedKeyFile.self, from: fileData)
            
            // Import the key
            let keyManagementService = KeyManagementService()
            _ = try await keyManagementService.importKey(
                name: sharedKey.name,
                keyData: sharedKey.keyData,
                pin: pin
            )
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Processed pending key file: \(sharedKey.name)")
            await MainActor.run {
                shouldRefreshKeys = true
                keyImportSuccess = sharedKey.name
            }
        } catch {
            print("❌ Failed to process pending .lfkey file: \(error)")
            // Keep the file for retry on next unlock
        }
    }
    
    /// Process a pending .locaphoto file from temp location
    private func processPendingLocaphotoFile(tempURL: URL) async {
        // Check if file still exists (might have been processed by handler)
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            print("ℹ️ Temp .locaphoto file already processed: \(tempURL.lastPathComponent)")
            return
        }
        
        do {
            let sharingService = SharingService()
            let photo = try await sharingService.handleIncomingShare(from: tempURL)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Processed pending .locaphoto file: \(photo.id)")
            await MainActor.run {
                shouldRefreshGallery = true
            }
        } catch {
            print("❌ Failed to process pending .locaphoto file: \(error)")
            // Keep the file for retry on next unlock
        }
    }

    /// Create main album
    func createMainAlbum(keyName: String) async {
        do {
            _ = try await albumService.createAlbum(name: "Main", keyName: keyName, isMain: true)
            needsMainAlbumSetup = false
        } catch {
            print("Failed to create main album: \(error)")
        }
    }

    /// Lock the app
    func lock() {
        currentPin = nil
        isUnlocked = false
    }

    /// Wait for app to be unlocked (for background imports)
    /// Returns immediately if app is already unlocked
    func waitForUnlock() async {
        // If already unlocked, return immediately
        if isUnlocked {
            return
        }
        // Otherwise, wait for unlock
        while !isUnlocked {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
}
