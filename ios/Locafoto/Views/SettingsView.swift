import SwiftUI
import Photos

/// Thumbnail style options
enum ThumbnailStyle: Int, CaseIterable {
    case lowRes = 0      // 64x64, pixelated when expanded
    case blurred = 1     // 128x128 with blur
    case crisp = 2       // 128x128, clear

    var displayName: String {
        switch self {
        case .lowRes: return "Low Resolution (64x64)"
        case .blurred: return "Blurred (128x128)"
        case .crisp: return "Crisp (128x128)"
        }
    }

    var description: String {
        switch self {
        case .lowRes: return "Maximum privacy - thumbnails are pixelated"
        case .blurred: return "Balanced - thumbnails are slightly blurred"
        case .crisp: return "Best quality - clear thumbnails"
        }
    }

    var size: CGFloat {
        switch self {
        case .lowRes: return 64
        case .blurred: return 128
        case .crisp: return 200  // Match gallery grid (100pt * 2x retina)
        }
    }

    var shouldBlur: Bool {
        return self == .blurred
    }
}

struct SettingsView: View {
    @AppStorage("autoDeleteFromCameraRoll") private var autoDeleteFromCameraRoll = false
    @AppStorage("preserveMetadata") private var preserveMetadata = true
    @AppStorage("generateThumbnails") private var generateThumbnails = true
    @AppStorage("thumbnailStyle") private var thumbnailStyleRaw = ThumbnailStyle.blurred.rawValue
    @State private var photoAccessStatus: String = "Unknown"
    @State private var receivedFiles: [ReceivedFileInfo] = []
    @State private var orphanedPhotos: [OrphanedPhotoInfo] = []
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: ReceivedFileInfo?
    @State private var orphanToDelete: OrphanedPhotoInfo?

    private var thumbnailStyle: ThumbnailStyle {
        ThumbnailStyle(rawValue: thumbnailStyleRaw) ?? .blurred
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Photo Library Access")) {
                    HStack {
                        Text("Current Access")
                        Spacer()
                        Text(photoAccessStatus)
                            .foregroundColor(.secondary)
                    }

                    Button("Manage Photo Access") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }

                    Text("Choose 'All Photos' for full access or 'Selected Photos' to limit which photos the app can see")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Privacy")) {
                    Toggle("Preserve Photo Metadata", isOn: $preserveMetadata)

                    Text("Keep EXIF data including location, camera settings, and timestamps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Thumbnail Style")) {
                    Picker("Style", selection: $thumbnailStyleRaw) {
                        ForEach(ThumbnailStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(thumbnailStyle.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Import")) {
                    Toggle("Auto-delete from Camera Roll", isOn: $autoDeleteFromCameraRoll)

                    Text("Automatically delete photos from Camera Roll after importing to Locafoto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Performance")) {
                    Toggle("Generate Thumbnails", isOn: $generateThumbnails)

                    Text("Create smaller thumbnails for faster gallery browsing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Security")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("End-to-end encryption", systemImage: "lock.fill")
                            .foregroundColor(.green)

                        Label("Photos never leave your device unencrypted", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)

                        Label("AirDrop sharing uses encrypted transfer", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }

                // Storage Management - Received Files
                Section(header: Text("Received Files")) {
                    if receivedFiles.isEmpty {
                        Text("No received files")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(receivedFiles) { file in
                            HStack {
                                Image(systemName: file.type == "lfs" ? "doc.fill" : "key.fill")
                                    .foregroundColor(file.type == "lfs" ? .locafotoPrimary : .locafotoAccent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.filename)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(file.formattedSize)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    fileToDelete = file
                                    showDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button("Delete All Received Files") {
                            deleteAllReceivedFiles()
                        }
                        .foregroundColor(.red)
                    }

                    Text("Files received via AirDrop are saved here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Orphaned Photos (on disk but not in gallery)
                Section(header: Text("Orphaned Data")) {
                    if orphanedPhotos.isEmpty {
                        Text("No orphaned photos")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(orphanedPhotos) { orphan in
                            HStack {
                                Image(systemName: "photo.fill")
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(orphan.photoId)
                                        .font(.caption)
                                        .lineLimit(1)
                                    HStack {
                                        if let keyName = orphan.keyName {
                                            Label(keyName, systemImage: "key.fill")
                                                .font(.caption2)
                                                .foregroundColor(.locafotoPrimary)
                                        }
                                        Text(orphan.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Button(action: {
                                    orphanToDelete = orphan
                                    showDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button("Delete All Orphaned Data") {
                            deleteAllOrphanedPhotos()
                        }
                        .foregroundColor(.red)
                    }

                    Text("Encrypted photos on disk that aren't linked to the gallery (e.g., after reinstall)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                checkPhotoAccessStatus()
                loadReceivedFiles()
                loadOrphanedPhotos()
            }
            .alert("Delete File", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    fileToDelete = nil
                    orphanToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let file = fileToDelete {
                        deleteReceivedFile(file)
                        fileToDelete = nil
                    }
                    if let orphan = orphanToDelete {
                        deleteOrphanedPhoto(orphan)
                        orphanToDelete = nil
                    }
                }
            } message: {
                if fileToDelete != nil {
                    Text("Are you sure you want to delete this received file?")
                } else if orphanToDelete != nil {
                    Text("Are you sure you want to delete this orphaned photo? This cannot be undone.")
                }
            }
        }
    }

    private func checkPhotoAccessStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            photoAccessStatus = "All Photos"
        case .limited:
            photoAccessStatus = "Selected Photos"
        case .denied:
            photoAccessStatus = "Denied"
        case .restricted:
            photoAccessStatus = "Restricted"
        case .notDetermined:
            photoAccessStatus = "Not Set"
        @unknown default:
            photoAccessStatus = "Unknown"
        }
    }

    private func loadReceivedFiles() {
        let fileManager = FileManager.default
        var files: [ReceivedFileInfo] = []

        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let receivedDir = appSupport.appendingPathComponent("Locafoto/Received")

        // Load LFS files
        let lfsDir = receivedDir.appendingPathComponent("lfs")
        if let lfsFiles = try? fileManager.contentsOfDirectory(at: lfsDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in lfsFiles {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                files.append(ReceivedFileInfo(
                    id: url.lastPathComponent,
                    filename: url.lastPathComponent,
                    path: url,
                    size: Int64(size),
                    type: "lfs"
                ))
            }
        }

        // Load key files
        let keysDir = receivedDir.appendingPathComponent("keys")
        if let keyFiles = try? fileManager.contentsOfDirectory(at: keysDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in keyFiles {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                files.append(ReceivedFileInfo(
                    id: url.lastPathComponent,
                    filename: url.lastPathComponent,
                    path: url,
                    size: Int64(size),
                    type: "key"
                ))
            }
        }

        receivedFiles = files.sorted { $0.filename < $1.filename }
    }

    private func loadOrphanedPhotos() {
        Task {
            let fileManager = FileManager.default
            var orphans: [OrphanedPhotoInfo] = []

            guard let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ) else { return }

            let photosDir = appSupport.appendingPathComponent("Locafoto/Photos")
            let trackingService = LFSFileTrackingService()

            // Get all photo IDs that are in the gallery
            let galleryPhotoIds = Set(await PhotoStore.shared.getAll().map { $0.id })

            // Get all encrypted files on disk
            guard let encryptedFiles = try? fileManager.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: [.fileSizeKey]) else {
                return
            }

            for url in encryptedFiles where url.pathExtension == "encrypted" {
                let photoIdString = url.deletingPathExtension().lastPathComponent
                guard let photoId = UUID(uuidString: photoIdString) else { continue }

                // Check if this photo is in the gallery
                if !galleryPhotoIds.contains(photoId) {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                    // Try to get key name from tracking
                    let keyName = try? await trackingService.getTrackingInfo(forPhotoId: photoId)?.keyName

                    orphans.append(OrphanedPhotoInfo(
                        id: photoIdString,
                        photoId: photoIdString,
                        path: url,
                        size: Int64(size),
                        keyName: keyName
                    ))
                }
            }

            await MainActor.run {
                orphanedPhotos = orphans.sorted { $0.photoId < $1.photoId }
            }
        }
    }

    private func deleteReceivedFile(_ file: ReceivedFileInfo) {
        try? FileManager.default.removeItem(at: file.path)
        loadReceivedFiles()
    }

    private func deleteAllReceivedFiles() {
        for file in receivedFiles {
            try? FileManager.default.removeItem(at: file.path)
        }
        loadReceivedFiles()
    }

    private func deleteOrphanedPhoto(_ orphan: OrphanedPhotoInfo) {
        Task {
            let fileManager = FileManager.default

            // Delete encrypted photo
            try? fileManager.removeItem(at: orphan.path)

            // Delete thumbnail if exists
            if let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ) {
                let thumbPath = appSupport.appendingPathComponent("Locafoto/Thumbnails/\(orphan.photoId).thumb")
                try? fileManager.removeItem(at: thumbPath)
            }

            // Delete tracking info
            if let photoId = UUID(uuidString: orphan.photoId) {
                let trackingService = LFSFileTrackingService()
                try? await trackingService.deleteTracking(byPhotoId: photoId)
            }

            await MainActor.run {
                loadOrphanedPhotos()
            }
        }
    }

    private func deleteAllOrphanedPhotos() {
        Task {
            for orphan in orphanedPhotos {
                let fileManager = FileManager.default

                try? fileManager.removeItem(at: orphan.path)

                if let appSupport = try? fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                ) {
                    let thumbPath = appSupport.appendingPathComponent("Locafoto/Thumbnails/\(orphan.photoId).thumb")
                    try? fileManager.removeItem(at: thumbPath)
                }

                if let photoId = UUID(uuidString: orphan.photoId) {
                    let trackingService = LFSFileTrackingService()
                    try? await trackingService.deleteTracking(byPhotoId: photoId)
                }
            }

            await MainActor.run {
                loadOrphanedPhotos()
            }
        }
    }
}

// MARK: - Helper Models

struct ReceivedFileInfo: Identifiable {
    let id: String
    let filename: String
    let path: URL
    let size: Int64
    let type: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct OrphanedPhotoInfo: Identifiable {
    let id: String
    let photoId: String
    let path: URL
    let size: Int64
    let keyName: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

#Preview {
    SettingsView()
}
