import SwiftUI

struct KeyLibraryView: View {
    @StateObject private var viewModel = KeyLibraryViewModel()
    @State private var showCreateKey = false
    @State private var showImportKey = false
    @State private var showDeleteConfirmation = false
    @State private var keyToDelete: KeyFile?
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Encryption Keys")
                .toolbar {
                    toolbarContent
                }
                .sheet(isPresented: $showCreateKey) {
                    createKeySheet
                }
                .sheet(isPresented: $showImportKey) {
                    importKeySheet
                }
                .onAppear {
                    Task {
                        await viewModel.loadKeys()
                    }
                }
                .alert("Delete Key", isPresented: $showDeleteConfirmation, presenting: keyToDelete) { key in
                    deleteAlertButtons(for: key)
                } message: { key in
                    deleteAlertMessage(for: key)
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if viewModel.keys.isEmpty {
            EmptyKeyLibraryView(onCreateKey: { showCreateKey = true })
        } else {
            keysList
        }
    }
    
    private var keysList: some View {
        List {
            statisticsSection
            keysSection
        }
    }
    
    private var statisticsSection: some View {
        Section(header: HStack {
            Text("Statistics")
            Spacer()
        }) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.blue)
                    .frame(width: 30)
                Text("Total Keys")
                Spacer()
                Text("\(viewModel.keys.count)")
                    .font(.headline)
            }

            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.green)
                    .frame(width: 30)
                Text("Files Encrypted")
                Spacer()
                Text("\(viewModel.totalFilesEncrypted)")
                    .font(.headline)
            }
        }
    }
    
    private var keysSection: some View {
        Section(header: Text("Encryption Keys")) {
            ForEach(viewModel.keys) { key in
                KeyRow(key: key, fileCount: viewModel.fileCount(for: key.name))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            keyToDelete = key
                            Task {
                                await viewModel.checkCanDelete(key)
                                showDeleteConfirmation = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button(action: { showCreateKey = true }) {
                    Label("Create New Key", systemImage: "key.fill")
                }

                Button(action: { showImportKey = true }) {
                    Label("Import Key File", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
    
    private var createKeySheet: some View {
        CreateKeyView { name in
            guard let pin = appState.currentPin else { return }
            await viewModel.createKey(name: name, pin: pin)
            showCreateKey = false
        }
    }
    
    private var importKeySheet: some View {
        ImportKeyView { name, keyData in
            guard let pin = appState.currentPin else { return }
            await viewModel.importKey(name: name, keyData: keyData, pin: pin)
            showImportKey = false
        }
    }
    
    @ViewBuilder
    private func deleteAlertButtons(for key: KeyFile) -> some View {
        let canDelete = viewModel.canDeleteKey(key)
        if canDelete {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteKey(key.id)
                }
            }
        } else {
            Button("OK", role: .cancel) { }
        }
    }
    
    @ViewBuilder
    private func deleteAlertMessage(for key: KeyFile) -> some View {
        let canDelete = viewModel.canDeleteKey(key)
        if canDelete {
            Text("This will permanently delete the encryption key '\(key.name)'. This action cannot be undone.")
        } else {
            let count = viewModel.fileCount(for: key.name)
            Text("Cannot delete this key. It is currently being used by \(count) file\(count == 1 ? "" : "s"). Delete the files first from the LFS Library.")
        }
    }
}

struct EmptyKeyLibraryView: View {
    let onCreateKey: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Encryption Keys")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create or import encryption keys to decrypt .lfs files shared with you")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onCreateKey) {
                Label("Create First Key", systemImage: "key.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct KeyRow: View {
    let key: KeyFile
    let fileCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.blue)

                Text(key.name)
                    .font(.headline)

                Spacer()

                if fileCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(fileCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            HStack {
                Text("Created: \(key.createdDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let lastUsed = key.lastUsed {
                    Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if fileCount > 0 {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Protected - \(fileCount) file\(fileCount == 1 ? "" : "s") using this key")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CreateKeyView: View {
    @Environment(\.dismiss) var dismiss
    @State private var keyName = ""
    @State private var isCreating = false

    let onCreate: (String) async -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Information")) {
                    TextField("Key Name", text: $keyName)
                }

                Section(footer: Text("This key will be used to encrypt/decrypt files. You can share files encrypted with this key, and anyone with the same key can decrypt them.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Create Encryption Key")
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
                            isCreating = true
                            await onCreate(keyName)
                            isCreating = false
                        }
                    }
                    .disabled(keyName.isEmpty || isCreating)
                }
            }
        }
    }
}

struct ImportKeyView: View {
    @Environment(\.dismiss) var dismiss
    @State private var keyName = ""
    @State private var keyHex = ""
    @State private var isImporting = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onImport: (String, Data) async -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Information")) {
                    TextField("Key Name", text: $keyName)
                }

                Section(header: Text("Key Data (Hex)")) {
                    TextEditor(text: $keyHex)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(footer: Text("Paste the 64-character hexadecimal key. This is typically a 256-bit AES key.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Import Encryption Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await importKey()
                        }
                    }
                    .disabled(keyName.isEmpty || keyHex.isEmpty || isImporting)
                }
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func importKey() async {
        isImporting = true

        // Convert hex string to Data
        let cleanHex = keyHex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard let keyData = Data(hexString: cleanHex) else {
            errorMessage = "Invalid hexadecimal format"
            showError = true
            isImporting = false
            return
        }

        guard keyData.count == 32 else {
            errorMessage = "Key must be exactly 32 bytes (64 hex characters)"
            showError = true
            isImporting = false
            return
        }

        await onImport(keyName, keyData)
        isImporting = false
    }
}

// Helper extension for hex string conversion
extension Data {
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)

        for i in 0..<length {
            let start = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let end = hexString.index(start, offsetBy: 2)
            let bytes = hexString[start..<end]

            guard let byte = UInt8(bytes, radix: 16) else {
                return nil
            }

            data.append(byte)
        }

        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    KeyLibraryView()
        .environmentObject(AppState())
}
