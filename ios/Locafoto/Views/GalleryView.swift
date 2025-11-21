import SwiftUI

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @EnvironmentObject var appState: AppState

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    colors: [
                        Color.locafotoLight,
                        Color.white,
                        Color.locafotoLight.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
                                // Playful header
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(viewModel.photos.count)")
                                            .font(.system(size: 48, weight: .black, design: .rounded))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.locafotoPrimary, .locafotoAccent],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                        Text(viewModel.photos.count == 1 ? "Memory" : "Memories")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.top, 10)

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
                    .fill(Color.locafotoLight)
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
                    .fill(Color.locafotoLight.opacity(0.5))
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

/// Photo gallery detail view with swipe navigation
struct PhotoGalleryDetailView: View {
    let photos: [Photo]
    let initialIndex: Int

    @State private var currentIndex: Int
    @State private var showShareSheet = false
    @State private var showShareOptions = false
    @State private var shareURL: URL?
    @EnvironmentObject var appState: AppState

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
                Button(action: { showShareOptions = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.locafotoAccent)
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
    }
}

/// Individual photo detail view (used within the gallery)
struct PhotoDetailView: View {
    let photo: Photo
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
