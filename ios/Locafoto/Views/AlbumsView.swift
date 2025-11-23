import SwiftUI
import UIKit

struct AlbumsView: View {
    @StateObject private var viewModel = AlbumViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showCreateAlbum = false
    @State private var albumToShare: Album?
    @State private var shareURLs: [URL] = []
    @State private var isPreparingShare = false
    @State private var showSortOptions = false
    @AppStorage("albumSortOption") private var albumSortOptionRaw = AlbumSortOption.modifiedDateDesc.rawValue

    private var currentSortOption: AlbumSortOption {
        AlbumSortOption(rawValue: albumSortOptionRaw) ?? .modifiedDateDesc
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Adaptive background for dark/light mode
                Color(.systemBackground)
                    .ignoresSafeArea()

                Group {
                    if viewModel.albums.isEmpty {
                        VStack(spacing: 30) {
                            ZStack {
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

                                Image(systemName: "rectangle.stack.fill")
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .floating()

                            VStack(spacing: 10) {
                                Text("No Albums Yet")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("Create an album to organize your photos")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            Button(action: { showCreateAlbum = true }) {
                                Label("Create Album", systemImage: "plus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.locafotoPrimary)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                                ForEach(viewModel.albums) { album in
                                    NavigationLink(destination: AlbumDetailView(album: album)) {
                                        AlbumCardView(album: album)
                                    }
                                    .contextMenu {
                                        Button {
                                            Task {
                                                await shareAlbum(album)
                                            }
                                        } label: {
                                            Label("Share Album", systemImage: "square.and.arrow.up")
                                        }
                                        .disabled(album.photoCount == 0)

                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteAlbum(album)
                                            }
                                        } label: {
                                            Label("Delete Album", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(AlbumSortOption.allCases, id: \.rawValue) { option in
                            Button {
                                albumSortOptionRaw = option.rawValue
                                viewModel.applySorting()
                            } label: {
                                HStack {
                                    Image(systemName: option.iconName)
                                    Text(option.displayName)
                                    if option.rawValue == albumSortOptionRaw {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.locafotoPrimary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateAlbum = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.locafotoPrimary)
                    }
                }
            }
            .sheet(isPresented: $showCreateAlbum) {
                CreateAlbumSheet(viewModel: viewModel)
            }
            .sheet(isPresented: .init(
                get: { !shareURLs.isEmpty },
                set: { if !$0 { shareURLs = [] } }
            )) {
                AlbumShareSheet(activityItems: shareURLs)
            }
            .overlay {
                if isPreparingShare {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Preparing album...")
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(16)
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadAlbums()
                    await viewModel.loadKeys()
                }
            }
            .onChange(of: albumSortOptionRaw) { _ in
                // Reload albums when sort option changes
                Task {
                    await viewModel.loadAlbums()
                }
            }
        }
    }

    private func shareAlbum(_ album: Album) async {
        guard let pin = appState.currentPin else {
            ToastManager.shared.showError("PIN not available")
            return
        }

        guard album.photoCount > 0 else {
            ToastManager.shared.showError("Album has no photos to share")
            return
        }

        await MainActor.run {
            isPreparingShare = true
        }

        do {
            let lfsService = LFSImportService()
            let urls = try await lfsService.createAlbumShareBundle(for: album, pin: pin)

            await MainActor.run {
                isPreparingShare = false
                shareURLs = urls
            }
        } catch {
            await MainActor.run {
                isPreparingShare = false
                ToastManager.shared.showError("Failed to prepare album: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Share Sheet

struct AlbumShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct AlbumCardView: View {
    let album: Album
    @State private var firstImage: UIImage?
    @State private var lastImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover image with overlay effect
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))

                    if album.isPrivate {
                        // Private album - show lock icon instead of thumbnail
                        VStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.locafotoPrimary)
                            Text("Private")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if album.photoCount == 0 {
                        // Empty album
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.locafotoPrimary.opacity(0.5))
                    } else if let first = firstImage {
                        if let last = lastImage {
                            // Two images - overlay effect
                            ZStack {
                                Image(uiImage: last)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width - 8, height: geometry.size.width - 8)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .offset(x: 4, y: 4)
                                    .opacity(0.7)

                                Image(uiImage: first)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.width)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else {
                            // Single image
                            Image(uiImage: first)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        // Loading
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(album.isPrivate ? Color.locafotoPrimary.opacity(0.5) : Color.locafotoPrimary.opacity(0.2), lineWidth: album.isPrivate ? 2 : 1)
            )
            .shadow(color: .locafotoPrimary.opacity(0.1), radius: 5)
            .clipped()

            // Album info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if album.isMain {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }

                    if album.isPrivate {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundColor(.locafotoPrimary)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .font(.caption2)
                    Text(album.keyName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)

                Text("\(album.photoCount) photos")
                    .font(.caption2)
                    .foregroundColor(.locafotoPrimary)
            }
        }
        .onAppear {
            // Don't load thumbnails for private albums
            if !album.isPrivate {
                loadAlbumThumbnails()
            }
        }
    }

    private func loadAlbumThumbnails() {
        Task {
            let storageService = StorageService()
            let encryptionService = EncryptionService()

            // Load first photo thumbnail
            if let firstPhotoId = album.firstPhotoId,
               let photo = await PhotoStore.shared.get(firstPhotoId) {
                do {
                    let imageData = try await storageService.loadThumbnail(for: firstPhotoId)
                    let decryptedData = try await encryptionService.decryptPhotoData(
                        imageData,
                        encryptedKey: photo.encryptedKeyData,
                        iv: photo.ivData,
                        authTag: photo.authTagData
                    )
                    await MainActor.run {
                        firstImage = UIImage(data: decryptedData)
                    }
                } catch {
                    print("Failed to load first thumbnail: \(error)")
                }
            }

            // Load last photo thumbnail (only if different from first)
            if let lastPhotoId = album.lastPhotoId,
               lastPhotoId != album.firstPhotoId,
               let photo = await PhotoStore.shared.get(lastPhotoId) {
                do {
                    let imageData = try await storageService.loadThumbnail(for: lastPhotoId)
                    let decryptedData = try await encryptionService.decryptPhotoData(
                        imageData,
                        encryptedKey: photo.encryptedKeyData,
                        iv: photo.ivData,
                        authTag: photo.authTagData
                    )
                    await MainActor.run {
                        lastImage = UIImage(data: decryptedData)
                    }
                } catch {
                    print("Failed to load last thumbnail: \(error)")
                }
            }
        }
    }
}

struct CreateAlbumSheet: View {
    @ObservedObject var viewModel: AlbumViewModel
    @Environment(\.dismiss) var dismiss

    @State private var albumName = ""
    @State private var selectedKeyName: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Name")) {
                    TextField("My Album", text: $albumName)
                }

                Section(header: Text("Encryption Key")) {
                    if viewModel.availableKeys.isEmpty {
                        Text("No keys available. Create one in the Keys tab first.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(viewModel.availableKeys) { key in
                            Button(action: {
                                selectedKeyName = key.name
                            }) {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.locafotoPrimary)
                                    Text(key.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedKeyName == key.name {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.locafotoPrimary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(footer: Text("Photos added to this album will be encrypted with the selected key.")) {
                    EmptyView()
                }
            }
            .navigationTitle("New Album")
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
                            guard let keyName = selectedKeyName, !albumName.isEmpty else { return }
                            _ = await viewModel.createAlbum(name: albumName, keyName: keyName)
                            dismiss()
                        }
                    }
                    .disabled(albumName.isEmpty || selectedKeyName == nil)
                }
            }
            .onAppear {
                // Auto-select first key
                if selectedKeyName == nil {
                    selectedKeyName = viewModel.availableKeys.first?.name
                }
            }
        }
    }
}

struct AlbumDetailView: View {
    let album: Album
    @State private var albumPhotos: [Photo] = []
    @State private var isAuthenticated = false
    @State private var showAuthSheet = false
    @State private var showPINSetup = false
    @State private var showPrivacyToggleConfirm = false
    @State private var currentAlbum: Album
    @State private var shareURLs: [URL] = []
    @State private var isPreparingShare = false
    @EnvironmentObject var appState: AppState
    @AppStorage("photoSortOption") private var photoSortOptionRaw = PhotoSortOption.captureDateDesc.rawValue

    private let albumService = AlbumService.shared
    private let biometricService = BiometricService()
    private let pinService = PrivateAlbumPINService()
    private let keyService = PrivateAlbumKeyService()

    init(album: Album) {
        self.album = album
        self._currentAlbum = State(initialValue: album)
    }

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.02).ignoresSafeArea()

            if currentAlbum.isPrivate && !isAuthenticated {
                // Show authentication required view
                VStack(spacing: 30) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.locafotoPrimary)

                    VStack(spacing: 8) {
                        Text("Private Album")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Authentication required to view photos")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showAuthSheet = true }) {
                        HStack {
                            Image(systemName: biometricService.isFaceIDAvailable() ? "faceid" : "lock.fill")
                            Text(biometricService.isFaceIDAvailable() ? "Authenticate with Face ID" : "Enter PIN")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.locafotoPrimary)
                        .cornerRadius(12)
                    }
                }
                .padding()
            } else if albumPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)

                    Text("No Photos")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Import or capture photos to add them to this album")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "key.fill")
                                        .font(.caption)
                                    Text(currentAlbum.keyName)
                                        .font(.caption)
                                }
                                .foregroundColor(.locafotoPrimary)

                                Text("\(albumPhotos.count) photos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(Array(albumPhotos.enumerated()), id: \.element.id) { index, photo in
                                NavigationLink(destination: PhotoGalleryDetailView(photos: albumPhotos, initialIndex: index)) {
                                    PhotoThumbnailView(photo: photo)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .navigationTitle(currentAlbum.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await shareAlbumFromDetail()
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(albumPhotos.isEmpty ? .secondary : .locafotoPrimary)
                    }
                    .disabled(albumPhotos.isEmpty)

                    Button(action: { showPrivacyToggleConfirm = true }) {
                        Image(systemName: currentAlbum.isPrivate ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(currentAlbum.isPrivate ? .locafotoPrimary : .secondary)
                    }
                }
            }
        }
        .sheet(isPresented: .init(
            get: { !shareURLs.isEmpty },
            set: { if !$0 { shareURLs = [] } }
        )) {
            AlbumShareSheet(activityItems: shareURLs)
        }
        .overlay {
            if isPreparingShare {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing album...")
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(16)
                }
            }
        }
        .onAppear {
            if !currentAlbum.isPrivate {
                isAuthenticated = true
                loadPhotos()
            }
        }
        .onChange(of: appState.shouldRefreshGallery) { shouldRefresh in
            if shouldRefresh && isAuthenticated {
                loadPhotos()
            }
        }
        .onChange(of: photoSortOptionRaw) { _ in
            if isAuthenticated {
                loadPhotos()
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            if biometricService.isFaceIDAvailable() {
                FaceIDPromptView(
                    albumName: currentAlbum.name,
                    onAuthenticate: {
                        do {
                            _ = try await biometricService.authenticate(reason: "Authenticate to access \(currentAlbum.name)")
                            return true
                        } catch {
                            return false
                        }
                    },
                    onSuccess: {
                        isAuthenticated = true
                        loadPhotos()
                    },
                    onCancel: {
                        showAuthSheet = false
                    }
                )
            } else {
                PINEntryView(
                    albumName: currentAlbum.name,
                    onVerify: { pin in
                        pinService.verifyPIN(pin)
                    },
                    onSuccess: {
                        isAuthenticated = true
                        loadPhotos()
                    }
                )
            }
        }
        .sheet(isPresented: $showPINSetup) {
            PrivateAlbumPINSetupView { pin in
                Task {
                    await togglePrivacy(pin: pin)
                }
            }
        }
        .alert(currentAlbum.isPrivate ? "Make Album Public?" : "Make Album Private?", isPresented: $showPrivacyToggleConfirm) {
            Button("Cancel", role: .cancel) { }
            Button(currentAlbum.isPrivate ? "Make Public" : "Make Private") {
                Task {
                    await handlePrivacyToggle()
                }
            }
        } message: {
            if currentAlbum.isPrivate {
                Text("Photos from this album will be visible in the All Photos gallery.")
            } else {
                Text("Photos from this album will be hidden from the All Photos gallery and will require Face ID or PIN to access.")
            }
        }
    }

    private func loadPhotos() {
        Task {
            var photos = await PhotoStore.shared.getPhotos(forAlbum: album.id)
            photos = sortPhotos(photos)
            albumPhotos = photos
        }
    }

    private func sortPhotos(_ photos: [Photo]) -> [Photo] {
        let sortOption = PhotoSortOption(rawValue: photoSortOptionRaw) ?? .captureDateDesc
        switch sortOption {
        case .captureDateDesc:
            return photos.sorted { $0.captureDate > $1.captureDate }
        case .captureDateAsc:
            return photos.sorted { $0.captureDate < $1.captureDate }
        case .importDateDesc:
            return photos.sorted { $0.importDate > $1.importDate }
        case .importDateAsc:
            return photos.sorted { $0.importDate < $1.importDate }
        case .sizeDesc:
            return photos.sorted { $0.originalSize > $1.originalSize }
        case .sizeAsc:
            return photos.sorted { $0.originalSize < $1.originalSize }
        }
    }

    private func handlePrivacyToggle() async {
        if currentAlbum.isPrivate {
            // Disable private mode
            await togglePrivacy(pin: nil)
        } else {
            // Enable private mode - check if auth is configured
            if biometricService.isFaceIDAvailable() {
                await togglePrivacy(pin: nil)
            } else if pinService.isPINSetUp() {
                await togglePrivacy(pin: nil)
            } else {
                // Need to set up PIN first
                await MainActor.run {
                    showPINSetup = true
                }
            }
        }
    }

    private func togglePrivacy(pin: String?) async {
        var updatedAlbum = currentAlbum
        updatedAlbum.isPrivate.toggle()

        do {
            if updatedAlbum.isPrivate {
                // Enable privacy - encrypt the album key
                if let appPin = appState.currentPin {
                    if biometricService.isFaceIDAvailable() {
                        try await keyService.enablePrivateMode(for: currentAlbum, currentAppPin: appPin)
                    } else if let privatePin = pin ?? (pinService.isPINSetUp() ? "" : nil) {
                        // Use PIN protection (if we just set up PIN, use that)
                        if !privatePin.isEmpty {
                            try pinService.setPIN(privatePin)
                        }
                        try await keyService.enablePrivateModeWithPIN(for: currentAlbum, currentAppPin: appPin, privateAlbumPIN: privatePin.isEmpty ? appPin : privatePin)
                    }
                }
            } else {
                // Disable privacy - remove protected key
                try await keyService.disablePrivateMode(for: currentAlbum)
            }

            // Update album in storage
            try await albumService.updateAlbum(updatedAlbum)

            await MainActor.run {
                currentAlbum = updatedAlbum
                appState.shouldRefreshGallery = true

                if updatedAlbum.isPrivate {
                    ToastManager.shared.showSuccess("Album is now private")
                } else {
                    ToastManager.shared.showSuccess("Album is now public")
                    isAuthenticated = true
                }
            }
        } catch {
            await MainActor.run {
                ToastManager.shared.showError("Failed to update privacy: \(error.localizedDescription)")
            }
        }
    }

    private func shareAlbumFromDetail() async {
        guard let pin = appState.currentPin else {
            ToastManager.shared.showError("PIN not available")
            return
        }

        guard !albumPhotos.isEmpty else {
            ToastManager.shared.showError("Album has no photos to share")
            return
        }

        await MainActor.run {
            isPreparingShare = true
        }

        do {
            let lfsService = LFSImportService()
            let urls = try await lfsService.createAlbumShareBundle(for: currentAlbum, pin: pin)

            await MainActor.run {
                isPreparingShare = false
                shareURLs = urls
            }
        } catch {
            await MainActor.run {
                isPreparingShare = false
                ToastManager.shared.showError("Failed to prepare album: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(AppState())
}
