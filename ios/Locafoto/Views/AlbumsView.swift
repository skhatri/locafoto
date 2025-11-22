import SwiftUI

struct AlbumsView: View {
    @StateObject private var viewModel = AlbumViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showCreateAlbum = false

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
            .onAppear {
                Task {
                    await viewModel.loadAlbums()
                    await viewModel.loadKeys()
                }
            }
        }
    }
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

                    if album.photoCount == 0 {
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
                    .stroke(Color.locafotoPrimary.opacity(0.2), lineWidth: 1)
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
            loadAlbumThumbnails()
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
    @EnvironmentObject var appState: AppState

    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.02).ignoresSafeArea()

            if albumPhotos.isEmpty {
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
                                    Text(album.keyName)
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
        .navigationTitle(album.name)
        .onAppear {
            Task {
                albumPhotos = await PhotoStore.shared.getPhotos(forAlbum: album.id)
            }
        }
        .onChange(of: appState.shouldRefreshGallery) { shouldRefresh in
            if shouldRefresh {
                Task {
                    albumPhotos = await PhotoStore.shared.getPhotos(forAlbum: album.id)
                }
            }
        }
    }
}

#Preview {
    AlbumsView()
        .environmentObject(AppState())
}
