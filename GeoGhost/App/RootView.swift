import SwiftData
import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case collection, series, capture, map, settings }

    @State private var tab: Tab = .collection
    @State private var lastContentTab: Tab = .collection
    @State private var showCapture = false
    @State private var storageWarningDismissed = false
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
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
        .environment(\.openCapture, OpenCaptureAction { showCapture = true })
        .alert("Your collection couldn't be opened",
               isPresented: Binding(get: { services.isRunningWithoutStorage && !storageWarningDismissed }, set: { if !$0 { storageWarningDismissed = true } })) {
            Button("Contact support") { openURL(URL(string: "https://passerbo.github.io/GeoGhost/support/")!) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("GeoGhost is running without saving, so anything you add now will be lost when you close the app. Restart GeoGhost; if this keeps happening, contact support.")
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

/// Lets screens deep in the tab hierarchy (e.g. empty states) start the capture flow.
struct OpenCaptureAction {
    let run: @MainActor () -> Void
    @MainActor func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var openCapture = OpenCaptureAction(run: {})
}
