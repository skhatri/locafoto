import SwiftUI
import Foundation
import CryptoKit
import AVKit
import MapKit

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @StateObject private var albumViewModel = AlbumViewModel()
    @EnvironmentObject var appState: AppState
    @State private var albums: [Album] = []
    @State private var showCreateAlbum = false
    @AppStorage("albumSortOption") private var albumSortOptionRaw = AlbumSortOption.modifiedDateDesc.rawValue
    @AppStorage("photoSortOption") private var photoSortOptionRaw = PhotoSortOption.captureDateDesc.rawValue

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    let albumColumns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]

    private let albumService = AlbumService.shared

    var body: some View {
        NavigationView {
            ZStack {
                // Adaptive background for dark/light mode
                Color(.systemBackground)
                    .ignoresSafeArea()

                Group {
                    if viewModel.photos.isEmpty {
                        ScrollView {
                            VStack(spacing: 20) {
                                // Albums section even when no photos
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Albums")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                        Spacer()

                                        Button(action: { showCreateAlbum = true }) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.locafotoPrimary)
                                        }
                                        .padding(.trailing, 8)

                                        if !albums.isEmpty {
                                            NavigationLink(destination: AlbumsListView(albums: albums)) {
                                                Text("See All")
                                                    .font(.subheadline)
                                                    .foregroundColor(.locafotoPrimary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)

                                    if albums.isEmpty {
                                        HStack {
                                            Spacer()
                                            VStack(spacing: 8) {
                                                Image(systemName: "rectangle.stack")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.secondary)
                                                Text("No albums yet")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.vertical, 20)
                                            Spacer()
                                        }
                                    } else {
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
                                }
                                .padding(.top, 10)

                                // No photos message
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

                                        Text("Let's make some memories!")
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
                            }
                        }
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

                                            Button(action: { showCreateAlbum = true }) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.locafotoPrimary)
                                            }
                                            .padding(.trailing, 8)

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
                    await albumViewModel.loadKeys()
                }
            }
            .sheet(isPresented: $showCreateAlbum) {
                CreateAlbumSheet(viewModel: albumViewModel)
                    .onDisappear {
                        Task {
                            await loadAlbums()
                        }
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
            .onChange(of: albumSortOptionRaw) { _ in
                // Reload albums when sort option changes
                Task {
                    await loadAlbums()
                }
            }
            .onChange(of: photoSortOptionRaw) { _ in
                // Reload photos when sort option changes
                Task {
                    await viewModel.loadPhotos()
                }
            }
        }
    }

    private func loadAlbums() async {
        // Use albumViewModel to load albums with sorting applied
        await albumViewModel.loadAlbums()
        albums = albumViewModel.albums
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

                if album.isPrivate {
                    // Private album - show lock icon
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.locafotoPrimary)
                        Text("Private")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                } else if album.photoCount == 0 {
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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(album.isPrivate ? Color.locafotoPrimary.opacity(0.5) : Color.clear, lineWidth: 1)
            )

            HStack(spacing: 2) {
                Text(album.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if album.isPrivate {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.locafotoPrimary)
                }
            }

            Text("\(album.photoCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            // Don't load thumbnails for private albums
            if !album.isPrivate {
                loadThumbnail()
            }
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

    @AppStorage("allowDeleteNonEmptyAlbums") private var allowDeleteNonEmptyAlbums = false
    @AppStorage("albumSortOption") private var albumSortOptionRaw = AlbumSortOption.modifiedDateDesc.rawValue
    @EnvironmentObject var appState: AppState
    @State private var albumToDelete: Album?
    @State private var showDeleteConfirmation = false
    @State private var localAlbums: [Album] = []

    private let albumService = AlbumService.shared

    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(localAlbums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        AlbumCardView(album: album)
                    }
                    .contextMenu {
                        // Always show delete option, but only allow if album is empty OR setting allows
                        if album.photoCount == 0 || allowDeleteNonEmptyAlbums {
                            Button(role: .destructive) {
                                albumToDelete = album
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Album", systemImage: "trash")
                            }
                        } else {
                            // Album has photos and setting is disabled - show disabled state
                            Text("Album has \(album.photoCount) photos")
                            Text("Enable 'Delete Non-Empty Albums' in Settings to delete")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Albums")
        .onAppear {
            // Load fresh data from disk with sorting
            Task {
                let viewModel = AlbumViewModel()
                await viewModel.loadAlbums()
                await MainActor.run {
                    localAlbums = viewModel.albums
                }
            }
        }
        .onChange(of: albumSortOptionRaw) { _ in
            // Reload albums when sort option changes
            Task {
                let viewModel = AlbumViewModel()
                await viewModel.loadAlbums()
                await MainActor.run {
                    localAlbums = viewModel.albums
                }
            }
        }
        .alert("Delete Album", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                albumToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let album = albumToDelete {
                    Task {
                        await deleteAlbum(album)
                    }
                }
            }
        } message: {
            if let album = albumToDelete {
                if album.photoCount > 0 {
                    Text("This will permanently delete the album '\(album.name)' and all \(album.photoCount) photos in it. This cannot be undone.")
                } else {
                    Text("This will permanently delete the album '\(album.name)'. This cannot be undone.")
                }
            }
        }
    }

    private func deleteAlbum(_ album: Album) async {
        do {
            // Delete all photos in the album first
            if album.photoCount > 0 {
                let photos = await PhotoStore.shared.getPhotos(forAlbum: album.id)
                let storageService = StorageService()
                let trackingService = LFSFileTrackingService()

                for photo in photos {
                    try? await trackingService.deleteTracking(byPhotoId: photo.id)
                    try? await storageService.deletePhoto(photo.id)
                }
            }

            // Delete the album
            try await albumService.deleteAlbum(album.id)

            // Update local state
            await MainActor.run {
                localAlbums.removeAll { $0.id == album.id }
                albumToDelete = nil
                appState.shouldRefreshGallery = true
            }
        } catch {
            print("Failed to delete album: \(error)")
        }
    }
}

// MARK: - Photo Thumbnail

struct PhotoThumbnailView: View {
    let photo: Photo
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            // Video indicator
            if photo.effectiveMediaType == .video {
                HStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                    if let duration = photo.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(4)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadThumbnail() {
        Task {
            do {
                let storageService = StorageService()
                let encryptionService = EncryptionService()

                let imageData = try await storageService.loadThumbnail(for: photo.id)

                // Decrypt thumbnail using thumbnail-specific encryption info if available
                // Fallback to main photo encryption info for backward compatibility (old photos)
                let thumbnailKey = photo.thumbnailEncryptedKeyData ?? photo.encryptedKeyData
                let thumbnailIv = photo.thumbnailIvData ?? photo.ivData
                let thumbnailAuthTag = photo.thumbnailAuthTagData ?? photo.authTagData
                
                let decryptedData = try await encryptionService.decryptPhotoData(
                    imageData,
                    encryptedKey: thumbnailKey,
                    iv: thumbnailIv,
                    authTag: thumbnailAuthTag
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
        .sheet(isPresented: Binding(
            get: { shareURL != nil && showShareSheet },
            set: { newValue in
                if !newValue {
                    showShareSheet = false
                    shareURL = nil
                }
            }
        )) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showShareOptions) {
            ShareOptionsView(photo: currentPhoto) { url in
                // Set URL first, then show sheet
                shareURL = url
                showShareSheet = true
            }
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
    @AppStorage("loopVideos") private var loopVideos = false
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var showMetadata = false
    @State private var metadataDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if photo.effectiveMediaType == .video {
                    // Video player
                    if let player = player {
                        VideoPlayer(player: player)
                            .onAppear {
                                player.play()
                                // Set up looping if enabled
                                if loopVideos {
                                    NotificationCenter.default.addObserver(
                                        forName: .AVPlayerItemDidPlayToEndTime,
                                        object: player.currentItem,
                                        queue: .main
                                    ) { _ in
                                        player.seek(to: .zero)
                                        player.play()
                                    }
                                }
                            }
                            .onDisappear {
                                player.pause()
                                NotificationCenter.default.removeObserver(
                                    self,
                                    name: .AVPlayerItemDidPlayToEndTime,
                                    object: player.currentItem
                                )
                            }
                    } else if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Failed to load video")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    if let image = fullImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = min(max(newScale, 0.5), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        // Reset to bounds
                                        if scale < 1 {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                scale = 1
                                                lastScale = 1
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        } else if scale > 4 {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                scale = 4
                                                lastScale = 4
                                            }
                                        }
                                        // Clamp offset after zooming
                                        clampOffset(in: geometry.size)
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: scale > 1 ? 0 : 10000)
                                    .onChanged { value in
                                        if scale > 1 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        if scale > 1 {
                                            lastOffset = offset
                                            clampOffset(in: geometry.size)
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                // Double tap to toggle zoom (centered)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if scale > 1 {
                                        // Reset to normal
                                        scale = 1
                                        lastScale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        // Zoom to 2.5x centered
                                        scale = 2.5
                                        lastScale = 2.5
                                        offset = .zero
                                        lastOffset = .zero
                                    }
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

                // Metadata panel overlay
                if showMetadata {
                    PhotoMetadataPanel(photo: photo, isShowing: $showMetadata)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        // Only trigger swipe-up when not zoomed
                        if scale <= 1 {
                            if value.translation.height < -50 {
                                // Swipe up - show metadata
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showMetadata = true
                                }
                            } else if value.translation.height > 50 && showMetadata {
                                // Swipe down - hide metadata
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showMetadata = false
                                }
                            }
                        }
                    }
            )
        }
        .onAppear {
            if photo.effectiveMediaType == .video {
                loadVideo()
            } else {
                loadFullImage()
            }
        }
        .onDisappear {
            // Clean up video temp file
            if let url = videoURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func loadVideo() {
        Task {
            do {
                let storageService = StorageService()
                let encryptionService = EncryptionService()
                let trackingService = LFSFileTrackingService()
                let keyManagementService = KeyManagementService()

                let videoData = try await storageService.loadPhoto(for: photo.id)

                // Check if this video is encrypted with LFS key
                let trackingInfo = try? await trackingService.getTrackingInfo(forPhotoId: photo.id)

                let decryptedData: Data

                if let tracking = trackingInfo, let pin = appState.currentPin {
                    // Video is encrypted with LFS key
                    print("🔓 Decrypting video with LFS key: \(tracking.keyName)")

                    let lfsKey = try await keyManagementService.getKey(byName: tracking.keyName, pin: pin)

                    let iv = tracking.iv ?? photo.ivData
                    let authTag = tracking.authTag ?? photo.authTagData

                    let nonce = try AES.GCM.Nonce(data: iv)
                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: videoData, tag: authTag)
                    decryptedData = try AES.GCM.open(sealedBox, using: lfsKey)
                } else {
                    // Video is encrypted with master key
                    print("🔓 Decrypting video with master key")
                    decryptedData = try await encryptionService.decryptPhotoData(
                        videoData,
                        encryptedKey: photo.encryptedKeyData,
                        iv: photo.ivData,
                        authTag: photo.authTagData
                    )
                }

                // Write to temp file for AVPlayer
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(photo.format.isEmpty ? "mp4" : photo.format)

                try decryptedData.write(to: tempURL)

                await MainActor.run {
                    videoURL = tempURL
                    player = AVPlayer(url: tempURL)
                    isLoading = false
                }
            } catch {
                print("Failed to load video: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func clampOffset(in size: CGSize) {
        // Calculate maximum allowed offset based on scale
        let maxOffsetX = max(0, (size.width * (scale - 1)) / 2)
        let maxOffsetY = max(0, (size.height * (scale - 1)) / 2)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            offset = CGSize(
                width: min(max(offset.width, -maxOffsetX), maxOffsetX),
                height: min(max(offset.height, -maxOffsetY), maxOffsetY)
            )
            lastOffset = offset
        }
    }

    private func loadFullImage() {
        Task {
            do {
                let storageService = StorageService()
                let encryptionService = EncryptionService()
                let trackingService = LFSFileTrackingService()
                let keyManagementService = KeyManagementService()

                let imageData = try await storageService.loadPhoto(for: photo.id)

                // Check if this photo is encrypted with LFS key (has tracking info)
                let trackingInfo = try? await trackingService.getTrackingInfo(forPhotoId: photo.id)
                
                let decryptedData: Data
                
                if let tracking = trackingInfo, let pin = appState.currentPin {
                    // Photo is encrypted with LFS key - decrypt using LFS key
                    print("🔓 Decrypting photo with LFS key: \(tracking.keyName)")
                    
                    // Get the LFS encryption key
                    let lfsKey = try await keyManagementService.getKey(byName: tracking.keyName, pin: pin)
                    
                    // Use IV and authTag from tracking if available, otherwise from Photo model
                    let iv = tracking.iv ?? photo.ivData
                    let authTag = tracking.authTag ?? photo.authTagData
                    
                    // Decrypt with LFS key directly (not master key)
                    let nonce = try AES.GCM.Nonce(data: iv)
                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: imageData, tag: authTag)
                    decryptedData = try AES.GCM.open(sealedBox, using: lfsKey)
                } else {
                    // Photo is encrypted with master key - decrypt using Photo model encryption info
                    print("🔓 Decrypting photo with master key")
                    decryptedData = try await encryptionService.decryptPhotoData(
                        imageData,
                        encryptedKey: photo.encryptedKeyData,
                        iv: photo.ivData,
                        authTag: photo.authTagData
                    )
                }

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

// MARK: - Photo Metadata Panel

struct PhotoMetadataPanel: View {
    let photo: Photo
    @Binding var isShowing: Bool

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Original capture info
                        MetadataSectionView(title: "Original") {
                            MetadataRow(icon: "calendar", label: "Captured", value: dateFormatter.string(from: photo.captureDate))

                            if let width = photo.width, let height = photo.height {
                                MetadataRow(icon: "aspectratio", label: "Dimensions", value: "\(width) × \(height)")
                            }

                            MetadataRow(icon: "doc", label: "Format", value: photo.format.uppercased())

                            MetadataRow(icon: "internaldrive", label: "Size", value: fileSizeFormatter.string(fromByteCount: photo.originalSize))

                            if photo.effectiveMediaType == .video, let duration = photo.duration {
                                MetadataRow(icon: "play.rectangle", label: "Duration", value: formatDuration(duration))
                            }
                        }

                        // Location info (if available)
                        if let latitude = photo.latitude, let longitude = photo.longitude {
                            MetadataSectionView(title: "Location") {
                                // Inline map preview
                                Map(coordinateRegion: .constant(MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                )), annotationItems: [PhotoLocation(latitude: latitude, longitude: longitude)]) { location in
                                    MapMarker(coordinate: location.coordinate, tint: .locafotoPrimary)
                                }
                                .frame(height: 150)
                                .cornerRadius(12)
                                .allowsHitTesting(false)

                                MetadataRow(icon: "location.fill", label: "Coordinates", value: formatCoordinates(latitude: latitude, longitude: longitude))

                                Button(action: {
                                    openInMaps(latitude: latitude, longitude: longitude)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "map.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.locafotoPrimary)
                                            .frame(width: 20)

                                        Text("Open in Maps")
                                            .font(.subheadline)
                                            .foregroundColor(.locafotoPrimary)

                                        Spacer()

                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(.locafotoPrimary)
                                    }
                                }
                            }
                        }

                        // Import info
                        MetadataSectionView(title: "Locafoto") {
                            MetadataRow(icon: "square.and.arrow.down", label: "Imported", value: dateFormatter.string(from: photo.importDate))

                            MetadataRow(icon: "clock", label: "Modified", value: dateFormatter.string(from: photo.modifiedDate))

                            MetadataRow(icon: "lock.shield", label: "Encrypted Size", value: fileSizeFormatter.string(fromByteCount: photo.encryptedSize))

                            MetadataRow(icon: photo.effectiveMediaType == .video ? "video.fill" : "photo.fill",
                                       label: "Type",
                                       value: photo.effectiveMediaType == .video ? "Video" : "Photo")
                        }

                        // Tags if any
                        if !photo.tags.isEmpty {
                            MetadataSectionView(title: "Tags") {
                                WrappingHStack(spacing: 8) {
                                    ForEach(photo.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.locafotoPrimary.opacity(0.2))
                                            .foregroundColor(.locafotoPrimary)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }

                        // Status indicators
                        HStack(spacing: 16) {
                            if photo.isFavorite {
                                Label("Favorite", systemImage: "heart.fill")
                                    .font(.caption)
                                    .foregroundColor(.pink)
                            }

                            if photo.isHidden {
                                Label("Hidden", systemImage: "eye.slash.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
            )
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height > 100 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isShowing = false
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    private func formatCoordinates(latitude: Double, longitude: Double) -> String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(latitude), latDir, abs(longitude), lonDir)
    }

    private func openInMaps(latitude: Double, longitude: Double) {
        let urlString = "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=Photo%20Location"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Metadata Section View

struct MetadataSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.locafotoPrimary)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.locafotoPrimary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Photo Location for Map

struct PhotoLocation: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Wrapping HStack for Tags (iOS 15 compatible)

struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // Simple horizontal scroll for iOS 15 compatibility
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
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
                Section(header: Text("Select Encryption Key")) {
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
                                        Text("Encrypt photo with this key")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if isLoading {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isLoading)
                        }
                    }
                }
                
                Section(footer: Text("The photo will be decrypted and re-encrypted with the selected key. Make sure the recipient has this key.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Share Photo")
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
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                    }
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

    private func shareAsLFS(keyName: String) async {
        guard let pin = appState.currentPin else {
            await MainActor.run {
                ToastManager.shared.showError("No PIN available")
                dismiss()
            }
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            let lfsService = LFSImportService()
            let url = try await lfsService.createLFSFile(for: photo, keyName: keyName, pin: pin)

            await MainActor.run {
                isLoading = false
                // Set URL and show sheet before dismissing
                onShare(url)
                // Small delay to ensure URL is set before dismissing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    dismiss()
                }
            }
        } catch {
            print("Failed to create .lfs file: \(error)")
            await MainActor.run {
                ToastManager.shared.showError("Failed to create .lfs file: \(error.localizedDescription)")
                isLoading = false
            }
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

    private let albumService = AlbumService.shared

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
            .onAppear {
                Task {
                    try? await albumService.loadAlbums()
                    albums = await albumService.getAllAlbums()
                }
            }
        }
    }

    private func movePhoto(to targetAlbum: Album) async {
        guard appState.currentPin != nil else {
            ToastManager.shared.showError("No PIN available")
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
            ToastManager.shared.showError(error.localizedDescription)
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
