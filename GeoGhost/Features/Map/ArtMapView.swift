import MapKit
import SwiftData
import SwiftUI

/// Every collected piece on a map, clustered by screen-space grid.
struct ArtMapView: View {
    @Query private var artworks: [Artwork]
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selected: Artwork?
    @State private var selectedCluster: Cluster?
    @State private var showUserLocation = false

    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: .all) {
                if showUserLocation { UserAnnotation() }
                ForEach(clusters) { cluster in
                    Annotation("", coordinate: cluster.center) {
                        if cluster.artworks.count == 1, let a = cluster.artworks.first {
                            ArtworkPin(artwork: a).onTapGesture { selected = a }
                        } else {
                            ClusterPin(cluster: cluster).onTapGesture { selectedCluster = cluster }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapUserLocationButton() }
            .onMapCameraChange(frequency: .onEnd) { ctx in visibleRegion = ctx.region }
            .overlay {
                if artworks.isEmpty {
                    EmptyStateView(systemImage: "map", title: "Nothing on the map yet", message: "Pieces with a location appear here as you collect them.")
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(item: $selected) { a in
                NavigationStack { ArtworkDetailView(artwork: a) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedCluster) { c in
                ClusterSheet(cluster: c) { a in selectedCluster = nil; selected = a }
                    .presentationDetents([.medium, .large])
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { showUserLocation = CLLocationManager().authorizationStatus == .authorizedWhenInUse }
        }
    }

    // MARK: Clustering

    struct Cluster: Identifiable, Hashable {
        let id: String
        let center: CLLocationCoordinate2D
        let artworks: [Artwork]
        static func == (l: Cluster, r: Cluster) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    private var clusters: [Cluster] {
        let located = artworks.filter { $0.coordinate != nil }
        guard !located.isEmpty else { return [] }
        // Grid cell ≈ 1/8 of the visible span; falls back to a coarse world grid before the first camera event.
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        let cellLat = max(span.latitudeDelta / 8, 0.00005)
        let cellLon = max(span.longitudeDelta / 8, 0.00005)
        var buckets: [String: [Artwork]] = [:]
        for a in located {
            let c = a.coordinate!
            let key = "\(Int(floor(c.latitude / cellLat)))_\(Int(floor(c.longitude / cellLon)))"
            buckets[key, default: []].append(a)
        }
        return buckets.map { key, items in
            let lat = items.map { $0.latitude! }.reduce(0, +) / Double(items.count)
            let lon = items.map { $0.longitude! }.reduce(0, +) / Double(items.count)
            return Cluster(id: key + "_\(items.count)", center: .init(latitude: lat, longitude: lon), artworks: items.sorted { $0.displayDate > $1.displayDate })
        }
    }
}

struct ClusterPin: View {
    let cluster: ArtMapView.Cluster
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let a = cluster.artworks.first { ArtworkPin(artwork: a, size: 48) }
            Text("\(cluster.artworks.count)")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .offset(x: 8, y: -8)
        }
    }
}

struct ClusterSheet: View {
    let cluster: ArtMapView.Cluster
    let onSelect: (Artwork) -> Void
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(cluster.artworks) { a in
                        Button { onSelect(a) } label: { StickerCard(artwork: a) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(PaperBackground())
            .navigationTitle("\(cluster.artworks.count) pieces here")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
