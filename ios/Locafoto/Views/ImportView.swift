import SwiftUI
import PhotosUI

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Import from Camera Roll")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Import existing photos from your camera roll and encrypt them securely in Locafoto.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Button(action: {
                    viewModel.showPhotoPicker = true
                }) {
                    Label("Select Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
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
                    Task {
                        await viewModel.importPhotos(results)
                    }
                }
            }
            .alert("Import Complete", isPresented: $viewModel.showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Successfully imported \(viewModel.importedCount) photos.")
            }
            .alert("Import Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Failed to import photos")
            }
        }
    }
}

struct PhotoPickerView: UIViewControllerRepresentable {
    let onPhotosSelected: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // No limit
        config.filter = .images

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
