import SwiftUI

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @EnvironmentObject var appState: AppState

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            Group {
                if viewModel.photos.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No photos yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Capture photos using the Camera tab or import from your library")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(viewModel.photos) { photo in
                                NavigationLink(destination: PhotoDetailView(photo: photo)) {
                                    PhotoThumbnailView(photo: photo)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.loadPhotos()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadPhotos()
                }
            }
            .onChange(of: appState.shouldRefreshGallery) { shouldRefresh in
                if shouldRefresh {
                    Task {
                        await viewModel.loadPhotos()
                        await MainActor.run {
                            appState.shouldRefreshGallery = false
                        }
                    }
                }
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: Photo
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
            } else if loadError {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                            Text("Failed")
                                .font(.caption2)
                        }
                        .foregroundColor(.red.opacity(0.7))
                    )
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task {
            do {
                let storageService = StorageService()
                let imageData = try await storageService.loadThumbnail(for: photo.id)

                // Decrypt thumbnail
                let encryptionService = EncryptionService()
                let decryptedData = try await encryptionService.decryptPhotoData(
                    imageData,
                    encryptedKey: photo.encryptedKeyData,
                    iv: photo.ivData,
                    authTag: photo.authTagData
                )

                await MainActor.run {
                    thumbnailImage = UIImage(data: decryptedData)
                    isLoading = false
                    loadError = (thumbnailImage == nil)
                }
            } catch {
                print("Failed to load thumbnail: \(error)")
                await MainActor.run {
                    isLoading = false
                    loadError = true
                }
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: Photo
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var showShareSheet = false
    @State private var showShareOptions = false
    @State private var shareURL: URL?
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = fullImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showShareOptions = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showShareOptions) {
            ShareOptionsView(photo: photo) { shareURL = $0; showShareSheet = true }
        }
        .onAppear {
            loadFullImage()
        }
    }

    private func loadFullImage() {
        Task {
            do {
                let storageService = StorageService()
                let imageData = try await storageService.loadPhoto(for: photo.id)

                // Decrypt photo
                let encryptionService = EncryptionService()
                let decryptedData = try await encryptionService.decryptPhotoData(
                    imageData,
                    encryptedKey: photo.encryptedKeyData,
                    iv: photo.ivData,
                    authTag: photo.authTagData
                )

                await MainActor.run {
                    fullImage = UIImage(data: decryptedData)
                    isLoading = false
                }
            } catch {
                print("Failed to load full image: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }


struct ShareOptionsView: View {
    let photo: Photo
    let onShare: (URL) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var keys: [KeyFile] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Share Format")) {
                    Button(action: {
                        Task {
                            await shareAsLocaphoto()
                        }
                    }) {
                        HStack {
                            Image(systemName: "lock.doc.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(".locaphoto")
                                    .font(.headline)
                                Text("Standard encrypted photo format")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("Share as .lfs (Locafoto Shared)")) {
                    if keys.isEmpty {
                        Text("No encryption keys available. Create one in the Keys tab.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(keys) { key in
                            Button(action: {
                                Task {
                                    await shareAsLFS(keyName: key.name)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading) {
                                        Text(key.name)
                                            .font(.headline)
                                        Text("Encrypt with this key")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task {
                    await loadKeys()
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    private func loadKeys() async {
        let keyManagementService = KeyManagementService()
        do {
            keys = try await keyManagementService.loadAllKeys()
        } catch {
            print("Failed to load keys: \(error)")
        }
    }

    private func shareAsLocaphoto() async {
        isLoading = true

        do {
            let sharingService = SharingService()
            let url = try await sharingService.createShareBundle(for: photo)

            await MainActor.run {
                onShare(url)
                dismiss()
                isLoading = false
            }
        } catch {
            print("Failed to create .locaphoto: \(error)")
            isLoading = false
        }
    }

    private func shareAsLFS(keyName: String) async {
        guard let pin = appState.currentPin else {
            print("No PIN available")
            return
        }

        isLoading = true

        do {
            let lfsService = LFSImportService()
            let url = try await lfsService.createLFSFile(for: photo, keyName: keyName, pin: pin)

            await MainActor.run {
                onShare(url)
                dismiss()
                isLoading = false
            }
        } catch {
            print("Failed to create .lfs file: \(error)")
            isLoading = false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

#Preview {
    GalleryView()
        .environmentObject(AppState())
}
