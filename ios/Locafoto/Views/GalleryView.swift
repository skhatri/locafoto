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

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
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
                }
            } catch {
                print("Failed to load thumbnail: \(error)")
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: Photo
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var showShareSheet = false
    @State private var shareURL: URL?

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
                Button(action: sharePhoto) {
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

    private func sharePhoto() {
        Task {
            do {
                let sharingService = SharingService()
                let url = try await sharingService.createShareBundle(for: photo)

                await MainActor.run {
                    shareURL = url
                    showShareSheet = true
                }
            } catch {
                print("Failed to create share bundle: \(error)")
            }
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
