import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    init() {
        // Configure translucent tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Configure translucent navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Gallery View
            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
                .tag(0)

            // Albums View
            AlbumsView()
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }
                .tag(1)

            // Camera View
            CameraView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(2)

            // Import View
            ImportView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .tag(3)

            // Key Library View
            KeyLibraryView()
                .tabItem {
                    Label("Keys", systemImage: "key.fill")
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
