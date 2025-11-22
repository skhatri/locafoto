import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showLFSFilePicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Import from Camera Roll")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Import existing photos from your camera roll and encrypt them with a selected key.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 20) {
                    Button(action: {
                        viewModel.showPhotoPicker = true
                    }) {
                        Label("Camera Roll", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        showLFSFilePicker = true
                    }) {
                        Label(".lfs Files", systemImage: "folder")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.locafotoPrimary)
                            .cornerRadius(10)
                    }
                }

                if viewModel.isImporting {
                    VStack(spacing: 10) {
                        ProgressView(value: viewModel.importProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 200)

                        Text("Importing \(viewModel.importedCount) of \(viewModel.totalCount) photos...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import")
            .sheet(isPresented: $viewModel.showPhotoPicker) {
                PhotoPickerView { results in
                    viewModel.onPhotosSelected(results)
                }
            }
            .sheet(isPresented: $viewModel.showKeySelection) {
                KeyAlbumSelectionSheet(
                    keys: viewModel.availableKeys,
                    albums: viewModel.availableAlbums,
                    photoCount: viewModel.pendingResults.count
                ) { keyName, albumId in
                    viewModel.showKeySelection = false
                    guard let pin = appState.currentPin else { return }
                    Task {
                        await viewModel.importPhotos(keyName: keyName, albumId: albumId, pin: pin)
                    }
                } onCancel: {
                    viewModel.showKeySelection = false
                }
            }
            .sheet(isPresented: $showLFSFilePicker) {
                LFSDocumentPickerView(
                    contentTypes: [UTType(filenameExtension: "lfs") ?? .data],
                    onPick: { url in
                        Task {
                            await importLFSFile(url)
                        }
                    }
                )
            }
        }
    }

    private func importLFSFile(_ url: URL) async {
        guard let pin = appState.currentPin else {
            ToastManager.shared.showError("No PIN available")
            return
        }

        do {
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "LFSImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let lfsService = LFSImportService()
            _ = try await lfsService.handleIncomingLFSFile(from: url, pin: pin)

            await MainActor.run {
                appState.shouldRefreshGallery = true
                ToastManager.shared.showSuccess("Successfully imported .lfs file")
            }
        } catch {
            ToastManager.shared.showError(error.localizedDescription)
        }
    }
}

// MARK: - LFS Document Picker

struct LFSDocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct KeyAlbumSelectionSheet: View {
    let keys: [KeyFile]
    let albums: [Album]
    let photoCount: Int
    let onSelect: (String, UUID) -> Void
    let onCancel: () -> Void

    @State private var selectedKeyName: String?
    @State private var selectedAlbumId: UUID?

    var body: some View {
        NavigationView {
            Group {
                if keys.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)

                        Text("No Encryption Keys")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Create an encryption key first in the Key Library before importing photos.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
                } else if albums.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)

                        Text("No Albums")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Create an album first in the Albums tab before importing photos.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        Section(header: Text("Select Encryption Key")) {
                            ForEach(keys) { key in
                                Button(action: {
                                    selectedKeyName = key.name
                                }) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.blue)

                                        VStack(alignment: .leading) {
                                            Text(key.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            Text("Created: \(key.createdDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if selectedKeyName == key.name {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }

                        Section(header: Text("Select Album")) {
                            ForEach(albums) { album in
                                Button(action: {
                                    selectedAlbumId = album.id
                                }) {
                                    HStack {
                                        Image(systemName: "rectangle.stack.fill")
                                            .foregroundColor(.locafotoPrimary)

                                        VStack(alignment: .leading) {
                                            Text(album.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            HStack(spacing: 4) {
                                                Image(systemName: "key.fill")
                                                    .font(.caption2)
                                                Text(album.keyName)
                                                    .font(.caption)
                                            }
                                            .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if selectedAlbumId == album.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.locafotoPrimary)
                                        }
                                    }
                                }
                            }
                        }

                        Section(footer: Text("\(photoCount) photo\(photoCount == 1 ? "" : "s") will be encrypted with the selected key and added to the selected album.")) {
                            EmptyView()
                        }
                    }
                }
            }
            .navigationTitle("Import Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if let keyName = selectedKeyName, let albumId = selectedAlbumId {
                            onSelect(keyName, albumId)
                        }
                    }
                    .disabled(selectedKeyName == nil || selectedAlbumId == nil)
                }
            }
            .onAppear {
                // Auto-select first key and album
                selectedKeyName = keys.first?.name
                selectedAlbumId = albums.first?.id
            }
        }
    }
}

struct PhotoPickerView: UIViewControllerRepresentable {
    let onPhotosSelected: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // No limit
        config.filter = .any(of: [.images, .videos])  // Support both

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhotosSelected: onPhotosSelected)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPhotosSelected: ([PHPickerResult]) -> Void

        init(onPhotosSelected: @escaping ([PHPickerResult]) -> Void) {
            self.onPhotosSelected = onPhotosSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            if !results.isEmpty {
                onPhotosSelected(results)
            }
        }
    }
}

#Preview {
    ImportView()
}
