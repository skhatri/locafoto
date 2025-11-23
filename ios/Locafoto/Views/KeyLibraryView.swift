import SwiftUI
import UniformTypeIdentifiers

struct KeyLibraryView: View {
    @StateObject private var viewModel = KeyLibraryViewModel()
    @State private var showCreateKey = false
    @State private var showImportKey = false
    @State private var showFilePicker = false
    @State private var showDeleteConfirmation = false
    @State private var keyToDelete: KeyFile?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
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
                .sheet(isPresented: $showFilePicker) {
                    DocumentPickerView(
                        contentTypes: [UTType(filenameExtension: "lfkey") ?? .data],
                        onPick: { url in
                            Task {
                                await importKeyFromFile(url)
                            }
                        }
                    )
                }
                .onAppear {
                    Task {
                        await viewModel.loadKeys()
                    }
                }
                .onChange(of: appState.shouldRefreshKeys) { shouldRefresh in
                    if shouldRefresh {
                        Task {
                            await viewModel.loadKeys()
                            await MainActor.run {
                                appState.shouldRefreshKeys = false
                            }
                        }
                    }
                }
                .alert("Delete Key", isPresented: $showDeleteConfirmation, presenting: keyToDelete) { key in
                    deleteAlertButtons(for: key)
                } message: { key in
                    deleteAlertMessage(for: key)
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
                        KeyShareSheet(items: [url])
                    }
                }
        }
    }
    
    private func shareKey(_ key: KeyFile) async {
        guard let pin = appState.currentPin else {
            ToastManager.shared.showError("No PIN available")
            return
        }
        
        do {
            let keyManagementService = KeyManagementService()
            let url = try await keyManagementService.exportKey(byName: key.name, pin: pin)
            
            await MainActor.run {
                // Set URL first, then show sheet
                shareURL = url
                showShareSheet = true
            }
        } catch {
            ToastManager.shared.showError("Failed to export key: \(error.localizedDescription)")
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
                KeyRow(
                    key: key,
                    fileCount: viewModel.fileCount(for: key.name),
                    onShare: {
                        Task {
                            await shareKey(key)
                        }
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Task {
                            await shareKey(key)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                    
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

                Button(action: { showFilePicker = true }) {
                    Label("Import from Files", systemImage: "folder")
                }

                Button(action: { showImportKey = true }) {
                    Label("Enter Key Manually", systemImage: "keyboard")
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
        } onCreateWithData: { name, keyData in
            guard let pin = appState.currentPin else { return }
            await viewModel.importKey(name: name, keyData: keyData, pin: pin)
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

    private func importKeyFromFile(_ url: URL) async {
        guard let pin = appState.currentPin else {
            ToastManager.shared.showError("No PIN available")
            return
        }

        do {
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "KeyImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Read the key file
            let fileData = try Data(contentsOf: url)

            // Decode the shared key structure
            let decoder = JSONDecoder()
            let sharedKey = try decoder.decode(SharedKeyFile.self, from: fileData)

            // Import the key
            await viewModel.importKey(name: sharedKey.name, keyData: sharedKey.keyData, pin: pin)
            ToastManager.shared.showSuccess("Key '\(sharedKey.name)' imported successfully")

        } catch {
            ToastManager.shared.showError(error.localizedDescription)
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
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.blue)

                Text(key.name)
                    .font(.headline)

                Spacer()
                
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                        .font(.body)
                }
                .buttonStyle(.plain)

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
    @State private var showAdvanced = false
    @State private var customKeyHex = ""

    let onCreate: (String) async -> Void
    let onCreateWithData: ((String, Data) async -> Void)?

    init(onCreate: @escaping (String) async -> Void, onCreateWithData: ((String, Data) async -> Void)? = nil) {
        self.onCreate = onCreate
        self.onCreateWithData = onCreateWithData
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Information")) {
                    TextField("Key Name", text: $keyName)
                }

                Section {
                    Toggle("Custom Key Data", isOn: $showAdvanced)
                }

                if showAdvanced {
                    Section(header: Text("Key Data (Hex)")) {
                        TextEditor(text: $customKeyHex)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    Section(footer: Text("Enter 64 hex characters (32 bytes) for a custom key. Leave empty to auto-generate.")) {
                        EmptyView()
                    }
                } else {
                    Section(footer: Text("A secure random key will be generated automatically. You can share files encrypted with this key.")) {
                        EmptyView()
                    }
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
                            await createKey()
                        }
                    }
                    .disabled(keyName.isEmpty || isCreating)
                }
            }
        }
    }

    private func createKey() async {
        isCreating = true

        if showAdvanced && !customKeyHex.isEmpty {
            // Custom key data
            let cleanHex = customKeyHex.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")

            guard let keyData = Data(hexString: cleanHex) else {
                ToastManager.shared.showError("Invalid hexadecimal format")
                isCreating = false
                return
            }

            guard keyData.count == 32 else {
                ToastManager.shared.showError("Key must be exactly 32 bytes (64 hex characters)")
                isCreating = false
                return
            }

            if let onCreateWithData = onCreateWithData {
                await onCreateWithData(keyName, keyData)
            }
        } else {
            // Auto-generate key
            await onCreate(keyName)
        }

        isCreating = false
    }
}

struct ImportKeyView: View {
    @Environment(\.dismiss) var dismiss
    @State private var keyName = ""
    @State private var keyHex = ""
    @State private var isImporting = false

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
        }
    }

    private func importKey() async {
        isImporting = true

        // Convert hex string to Data
        let cleanHex = keyHex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard let keyData = Data(hexString: cleanHex) else {
            ToastManager.shared.showError("Invalid hexadecimal format")
            isImporting = false
            return
        }

        guard keyData.count == 32 else {
            ToastManager.shared.showError("Key must be exactly 32 bytes (64 hex characters)")
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

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
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

// MARK: - Share Sheet

struct KeyShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

#Preview {
    KeyLibraryView()
        .environmentObject(AppState())
}
