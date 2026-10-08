import SwiftData
import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case collection, series, capture, map, settings }

    @State private var tab: Tab = .collection
    @State private var lastContentTab: Tab = .collection
    @State private var showCapture = false
    @Environment(\.modelContext) private var context
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
                showCapture = true
            } else {
                lastContentTab = new
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView()
        }
        .task {
            // Older pieces have no cached local features; compute them once and link what matches.
            let minInliers = UserDefaults.standard.object(forKey: "seriesMinInliers") as? Int ?? 8
            SeriesAssigner.matcher.matchInliers = minInliers
            SeriesAssigner.matcher.suggestionInliers = max(3, minInliers - 3)
            if artworks.contains(where: { $0.localFeatures == nil }) {
                await SeriesAssigner.backfillAndRematch(in: context)
            }
        }
    }
}
