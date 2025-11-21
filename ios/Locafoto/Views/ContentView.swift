import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Gallery View
            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
                .tag(0)

            // Camera View
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(1)

            // Import View
            ImportView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .tag(2)

            // Key Library View
            KeyLibraryView()
                .tabItem {
                    Label("Keys", systemImage: "key.fill")
                }
                .tag(3)

            // LFS Library View (NEW)
            LFSLibraryView()
                .tabItem {
                    Label("LFS Files", systemImage: "doc.badge.ellipsis")
                }
                .tag(4)

            // Settings View
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)
        }
        .tint(.locafotoPrimary)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
