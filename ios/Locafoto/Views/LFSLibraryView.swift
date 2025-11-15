import SwiftUI

struct LFSLibraryView: View {
    @StateObject private var viewModel = LFSLibraryViewModel()
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: LFSImportedFile?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.files.isEmpty {
                    EmptyLFSLibraryView()
                } else {
                    List {
                        Section(header: HStack {
                            Text("Statistics")
                            Spacer()
                        }) {
                            StatisticsRow(icon: "doc.fill", title: "Total Files", value: "\(viewModel.statistics.totalFiles)")
                            StatisticsRow(icon: "key.fill", title: "Keys Used", value: "\(viewModel.statistics.uniqueKeys)")
                            StatisticsRow(icon: "externaldrive.fill", title: "Total Size", value: formatBytes(viewModel.statistics.totalSize))
                        }

                        Section(header: Text("Imported Files")) {
                            ForEach(viewModel.files) { file in
                                LFSFileRow(file: file)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            fileToDelete = file
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("LFS Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.loadFiles()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadFiles()
                }
            }
            .alert("Delete File", isPresented: $showDeleteConfirmation, presenting: fileToDelete) { file in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteFile(file)
                    }
                }
            } message: { file in
                Text("This will delete the photo from your gallery and remove it from the LFS library. This action cannot be undone.")
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct EmptyLFSLibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No LFS Files")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import .lfs files via AirDrop to see them here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Track all imported .lfs files")
                        .font(.caption)
                }

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("View which key was used")
                        .font(.caption)
                }

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Manage and delete files")
                        .font(.caption)
                }
            }
            .padding()
        }
        .padding()
    }
}

struct StatisticsRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)

            Text(title)
                .font(.body)

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

struct LFSFileRow: View {
    let file: LFSImportedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.green)

                Text(file.originalFilename ?? "Untitled")
                    .font(.headline)

                Spacer()

                Text(formatBytes(file.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text(file.keyName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Imported: \(file.importDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    LFSLibraryView()
}
