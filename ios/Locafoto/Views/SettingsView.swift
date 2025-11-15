import SwiftUI

struct SettingsView: View {
    @AppStorage("autoDeleteFromCameraRoll") private var autoDeleteFromCameraRoll = false
    @AppStorage("preserveMetadata") private var preserveMetadata = true
    @AppStorage("generateThumbnails") private var generateThumbnails = true

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Privacy")) {
                    Toggle("Preserve Photo Metadata", isOn: $preserveMetadata)

                    Text("Keep EXIF data including location, camera settings, and timestamps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Import")) {
                    Toggle("Auto-delete from Camera Roll", isOn: $autoDeleteFromCameraRoll)

                    Text("Automatically delete photos from Camera Roll after importing to Locafoto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Performance")) {
                    Toggle("Generate Thumbnails", isOn: $generateThumbnails)

                    Text("Create smaller thumbnails for faster gallery browsing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Security")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("End-to-end encryption", systemImage: "lock.fill")
                            .foregroundColor(.green)

                        Label("Photos never leave your device unencrypted", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)

                        Label("AirDrop sharing uses encrypted transfer", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
