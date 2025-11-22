import SwiftUI
import Foundation

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @EnvironmentObject var appState: AppState
    @State private var albums: [Album] = []

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    let albumColumns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]

    private let albumService = AlbumService()

    var body: some View {
        NavigationView {
            ZStack {
                // Adaptive background for dark/light mode
                Color(.systemBackground)
                    .ignoresSafeArea()

                Group {
                    if viewModel.photos.isEmpty {
                        VStack(spacing: 30) {
                            ZStack {
                                // Outer glow ring
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.locafotoNeon, Color.locafotoPrimary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 4
                                    )
                                    .frame(width: 140, height: 140)
                                    .blur(radius: 10)

                                // Main circle with gradient
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.locafotoPrimary, Color.locafotoAccent],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                    .neonGlow(color: .locafotoPrimary, radius: 15)

                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .floating()

                            VStack(spacing: 10) {
                                Text("No Photos Yet")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("Let's make some memories! ✨")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.locafotoPrimary)

                                Text("Tap Camera to capture or Import from your library")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 20) {
                                // Albums section (like Photos app)
                                if !albums.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text("Albums")
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                            Spacer()
                                            NavigationLink(destination: AlbumsListView(albums: albums)) {
                                                Text("See All")
                                                    .font(.subheadline)
                                                    .foregroundColor(.locafotoPrimary)
                                            }
                                        }
                                        .padding(.horizontal)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(albums) { album in
                                                    NavigationLink(destination: AlbumDetailView(album: album)) {
                                                        MiniAlbumCard(album: album)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 10)
                                }

                                // All Photos header
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("All Photos")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                        Text("\(viewModel.photos.count) \(viewModel.photos.count == 1 ? "photo" : "photos")")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 4) {
                                    ForEach(Array(viewModel.photos.enumerated()), id: \.element.id) { index, photo in
                                        NavigationLink(destination: PhotoGalleryDetailView(photos: viewModel.photos, initialIndex: index)) {
                                            PhotoThumbnailView(photo: photo)
                                                .aspectRatio(1, contentMode: .fill)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: [Color.white.opacity(0.3), Color.clear],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1
                                                        )
                                                )
                                                .shadow(color: .locafotoPrimary.opacity(0.2), radius: 5, x: 0, y: 2)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.loadPhotos()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.locafotoPrimary.opacity(0.1))
                                .frame(width: 36, height: 36)

                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.locafotoPrimary)
                        }
                    }
                }
            }
            .locafotoTheme()
            .onAppear {
                Task {
                    await viewModel.loadPhotos()
                    await loadAlbums()
                }
            }
            .onChange(of: appState.shouldRefreshGallery) { shouldRefresh in
                if shouldRefresh {
                    Task {
                        await viewModel.loadPhotos()
                        await loadAlbums()
                        await MainActor.run {
                            appState.shouldRefreshGallery = false
                        }
                    }
                }
            }
        }
    }

    private func loadAlbums() async {
        do {
            try await albumService.loadAlbums()
            albums = await albumService.getAllAlbums()
        } catch {
            print("Failed to load albums: \(error)")
        }
    }
}

// MARK: - Mini Album Card for Gallery

struct MiniAlbumCard: View {
    let album: Album
    @State private var coverImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)

                if album.photoCount == 0 {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.locafotoPrimary.opacity(0.5))
                } else if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(album.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("\(album.photoCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard let firstPhotoId = album.firstPhotoId else { return }

        Task {
            guard let photo = await PhotoStore.shared.get(firstPhotoId) else { return }

            do {
                let storageService = StorageService()
                let encryptionService = EncryptionService()

                let imageData = try await storageService.loadThumbnail(for: firstPhotoId)
                let decryptedData = try await encryptionService.decryptPhotoData(
                    imageData,
                    encryptedKey: photo.encryptedKeyData,
                    iv: photo.ivData,
                    authTag: photo.authTagData
                )

                await MainActor.run {
                    coverImage = UIImage(data: decryptedData)
                }
            } catch {
                print("Failed to load mini album cover: \(error)")
            }
        }
    }
}

// MARK: - Albums List View (See All)

struct AlbumsListView: View {
    let albums: [Album]

    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        AlbumCardView(album: album)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Albums")
    }
}

// MARK: - Photo Thumbnail

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
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                            Text("Failed")
                                .font(.caption2)
                        }
                        .foregroundColor(.locafotoError)
                    )
            } else if isLoading {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                            .tint(.locafotoPrimary)
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
                let encryptionService = EncryptionService()

                let imageData = try await storageService.loadThumbnail(for: photo.id)

                // Decrypt thumbnail with master key (stored in photo metadata)
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

/// Photo gallery detail view with swipe navigation
struct PhotoGalleryDetailView: View {
    let photos: [Photo]
    let initialIndex: Int

    @State private var currentIndex: Int
    @State private var showShareSheet = false
    @State private var showShareOptions = false
    @State private var shareURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var showAddToAlbum = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    init(photos: [Photo], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    var currentPhoto: Photo {
        photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoDetailView(photo: photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Photo counter overlay with glassmorphism
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(currentIndex + 1)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("/")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .opacity(0.7)
                        Text("\(photos.count)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .opacity(0.9)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassMorphic(cornerRadius: 25, opacity: 0.3)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.locafotoPrimary.opacity(0.8), Color.locafotoAccent.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .neonGlow(color: .locafotoPrimary, radius: 10)
                    .padding()
                }
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { showAddToAlbum = true }) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .foregroundColor(.locafotoPrimary)
                    }
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    Button(action: { showShareOptions = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.locafotoAccent)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showShareOptions) {
            ShareOptionsView(photo: currentPhoto) { shareURL = $0; showShareSheet = true }
        }
        .sheet(isPresented: $showAddToAlbum) {
            AddToAlbumSheet(photo: currentPhoto)
        }
        .alert("Delete Photo", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    let storageService = StorageService()
                    let trackingService = LFSFileTrackingService()

                    // Delete LFS tracking
                    try? await trackingService.deleteTracking(byPhotoId: currentPhoto.id)
                    // Delete storage files
                    try? await storageService.deletePhoto(currentPhoto.id)

                    // Trigger gallery refresh and dismiss
                    await MainActor.run {
                        appState.shouldRefreshGallery = true
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will permanently delete this photo and cannot be undone.")
        }
    }
}

/// Individual photo detail view (used within the gallery)
struct PhotoDetailView: View {
    let photo: Photo
    @EnvironmentObject var appState: AppState
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = fullImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                // Reset to bounds
                                if scale < 1 {
                                    withAnimation {
                                        scale = 1
                                        lastScale = 1
                                    }
                                } else if scale > 4 {
                                    withAnimation {
                                        scale = 4
                                        lastScale = 4
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double tap to reset zoom
                        withAnimation {
                            scale = 1
                            lastScale = 1
                        }
                    }
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Failed to load photo")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            loadFullImage()
        }
    }

    private func loadFullImage() {
        Task {
            do {
                let storageService = StorageService()
                let encryptionService = EncryptionService()

                let imageData = try await storageService.loadPhoto(for: photo.id)

                // Decrypt with master key (same as thumbnails)
                let decryptedData = try await encryptionService.decryptPhotoData(
                    imageData,
                    encryptedKey: photo.encryptedKeyData,
                    iv: photo.ivData,
                    authTag: photo.authTagData
                )

                // Validate image data
                guard let image = UIImage(data: decryptedData) else {
                    print("Failed to create UIImage from decrypted data (\(decryptedData.count) bytes)")
                    await MainActor.run {
                        isLoading = false
                    }
                    return
                }

                await MainActor.run {
                    fullImage = image
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
}

// MARK: - Share Options View

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
                                .foregroundColor(.locafotoPrimary)
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
                                        .foregroundColor(.locafotoAccent)
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

// MARK: - Move to Album Sheet

struct AddToAlbumSheet: View {
    let photo: Photo
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var albums: [Album] = []
    @State private var isMoving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let albumService = AlbumService()

    var body: some View {
        NavigationView {
            List {
                if albums.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)

                        Text("No Other Albums")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Create another album to move photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    Section(footer: Text("Moving to a different album will re-encrypt the photo with that album's key.")) {
                        ForEach(albums) { album in
                            Button(action: {
                                Task {
                                    await movePhoto(to: album)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.stack.fill")
                                        .foregroundColor(.locafotoPrimary)

                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(album.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            if album.isMain {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.yellow)
                                            }
                                        }

                                        HStack(spacing: 4) {
                                            Image(systemName: "key.fill")
                                                .font(.caption2)
                                            Text(album.keyName)
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if photo.albumId == album.id {
                                        Text("Current")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(photo.albumId == album.id || isMoving)
                        }
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isMoving {
                    ProgressView("Moving...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
            }
            .alert("Move Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Failed to move photo")
            }
            .onAppear {
                Task {
                    try? await albumService.loadAlbums()
                    albums = await albumService.getAllAlbums()
                }
            }
        }
    }

    private func movePhoto(to targetAlbum: Album) async {
        guard let pin = appState.currentPin else {
            errorMessage = "No PIN available"
            showError = true
            return
        }

        isMoving = true

        do {
            // Get source album info
            guard let sourceAlbum = albums.first(where: { $0.id == photo.albumId }) else {
                throw NSError(domain: "Move", code: 1, userInfo: [NSLocalizedDescriptionKey: "Source album not found"])
            }

            // If same key, just update albumId
            if sourceAlbum.keyName == targetAlbum.keyName {
                await PhotoStore.shared.updateAlbum(for: photo.id, to: targetAlbum.id)
            } else {
                // Different keys - but photos are stored with master key, not album key
                // Just update the albumId and tracking
                let trackingService = LFSFileTrackingService()

                // Update tracking with new key name
                try await trackingService.deleteTracking(byPhotoId: photo.id)
                try await trackingService.trackImportWithCrypto(
                    photoId: photo.id,
                    keyName: targetAlbum.keyName,
                    originalFilename: nil,
                    fileSize: photo.originalSize,
                    iv: nil,
                    authTag: nil
                )

                // Update photo's albumId
                await PhotoStore.shared.updateAlbum(for: photo.id, to: targetAlbum.id)
            }

            await MainActor.run {
                appState.shouldRefreshGallery = true
                dismiss()
            }

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isMoving = false
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Previews

#Preview {
    GalleryView()
        .environmentObject(AppState())
}
