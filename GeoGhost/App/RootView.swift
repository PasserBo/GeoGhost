import SwiftData
import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case collection, series, capture, map, settings }

    @State private var tab: Tab = .collection
    @State private var lastContentTab: Tab = .collection
    @State private var showCapture = false
    @State private var showLimitAlert = false
    @Environment(AppServices.self) private var services
    @Query private var artworks: [Artwork]

    var body: some View {
        TabView(selection: $tab) {
            CollectionView().tabItem { Label("Collection", systemImage: "square.grid.2x2.fill") }.tag(Tab.collection)
            SeriesListView().tabItem { Label("Series", systemImage: "rectangle.stack.fill") }.tag(Tab.series)
            Color.clear.tabItem { Label("Capture", systemImage: "camera.fill") }.tag(Tab.capture)
            ArtMapView().tabItem { Label("Map", systemImage: "map.fill") }.tag(Tab.map)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(Tab.settings)
        }
        .onChange(of: tab) { _, new in
            // The middle tab is a button in disguise: open the capture flow and stay on the previous tab.
            if new == .capture {
                tab = lastContentTab
                if services.pro.canAddArtwork(currentCount: artworks.count) { showCapture = true } else { showLimitAlert = true }
            } else {
                lastContentTab = new
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView()
        }
        .alert("Free limit reached", isPresented: $showLimitAlert) {
            Button("See GeoGhost Pro") { tab = .settings }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The free version holds \(ProStore.freeLimit) pieces. Unlock Pro for an unlimited collection.")
        }
    }
}
