import MapKit
import SwiftData
import SwiftUI

/// The map page: one's own pieces (clustered on the phone) or, when online features exist, everyone's
/// public pieces (clustered by the server) — spec: explore-map.
struct ArtMapView: View {
    enum Mode: String { case mine, world }

    @Query private var artworks: [Artwork]
    @Services private var services
    @AppStorage("mapMode") private var modeRaw = Mode.mine.rawValue
    @State private var explore: ExploreModel?
    @State private var selectedPost: ExplorePost?
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var hasFramed = false
    @State private var selected: Artwork?
    @State private var selectedCluster: Cluster?
    @State private var showUserLocation = false
    @Environment(\.openCapture) private var openCapture

    /// `position` is where the map opens; UI snapshots use it to open the world map on a known area.
    init(position: MapCameraPosition = .automatic) {
        _position = State(initialValue: position)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: .all) {
                if showUserLocation { UserAnnotation() }
                if isWorldLive, let explore, let config = services.online?.config {
                    ForEach(explore.posts) { post in
                        Annotation("", coordinate: post.coordinate) {
                            if post.cellCount > 1 {
                                ExploreClusterPin(post: post, config: config).onTapGesture { zoom(into: post.coordinate) }
                            } else {
                                ExplorePostPin(post: post, config: config).onTapGesture { selectedPost = post }
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                } else {
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
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapUserLocationButton() }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                visibleRegion = ctx.region
                // Automatic framing is for opening the map only. Left on, it follows the pins: grouping
                // them for the new zoom moves them, the map frames them again, and that regroups them
                // once more — with pieces far apart it never settles.
                if !hasFramed {
                    hasFramed = true
                    position = .region(ctx.region)
                }
                if isWorldLive { explore?.regionChanged(ctx.region) }
            }
            .overlay(alignment: .bottom) {
                if isWorldLive {
                    VStack(spacing: 8) {
                        if let notice = services.onlineState?.appConfig.notice() {
                            OnlineNoticeView(text: notice).padding(.horizontal, 16)
                        }
                        if let explore { WorldStatusBanner(model: explore) }
                    }
                }
            }
            .overlay {
                if isWorld {
                    // Too old for online features: say so instead of loading anything (spec: online-availability).
                    if worldNeedsUpdate { UpdateRequiredView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) }
                } else if artworks.isEmpty {
                    EmptyStateView(systemImage: "map", title: "Nothing on the map yet", message: "Pieces with a location appear here as you collect them.",
                                   action: (label: "Collect a piece", run: { openCapture() }))
                        .background(.ultraThinMaterial)
                } else if !artworks.contains(where: { $0.coordinate != nil }) {
                    // Everything was captured with location off or imported without GPS.
                    EmptyStateView(systemImage: "location.slash", title: "None of your pieces have a location",
                                   message: "Pieces captured with location on, or imported photos that contain GPS data, appear here.")
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
            .sheet(item: $selectedPost) { post in
                if let config = services.online?.config {
                    RemotePostSheet(post: post, config: config, state: services.onlineState)
                        .presentationDetents([.medium, .large])
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if services.online != nil {
                    ToolbarItem(placement: .principal) {
                        Picker("Map", selection: $modeRaw) {
                            Text("Mine").tag(Mode.mine.rawValue)
                            Text("World").tag(Mode.world.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
            }
            .onChange(of: modeRaw) { startWorldIfNeeded() }
            .onChange(of: worldNeedsUpdate) { startWorldIfNeeded() }
            .onReceive(NotificationCenter.default.publisher(for: .onlineBlocksChanged)) { note in
                if let author = note.object as? UUID { explore?.authorBlocked(author) } else { explore?.invalidate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .onlinePostReported)) { note in
                if let post = note.object as? UUID { explore?.postReported(post) }
            }
            .task { startWorldIfNeeded() }
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                showUserLocation = CLLocationManager().authorizationStatus == .authorizedWhenInUse
                frameOwnPieces()
            }
        }
    }

    private var isWorld: Bool { modeRaw == Mode.world.rawValue && services.online != nil }
    private var worldNeedsUpdate: Bool { services.onlineState?.appConfig.updateRequired ?? false }
    /// The world map loads only when this version may use online features.
    private var isWorldLive: Bool { isWorld && !worldNeedsUpdate }

    private func startWorldIfNeeded() {
        guard isWorldLive, let online = services.online else { return }
        if explore == nil { explore = ExploreModel(client: ExploreClient(services: online)) }
        if let visibleRegion { explore?.regionChanged(visibleRegion) }
    }

    /// Opens on all of one's own pieces. Framed from the pieces themselves, not from the pins: before
    /// the first camera event every piece is in one pin, and framing that single point would zoom
    /// in on the middle of nowhere between them.
    private func frameOwnPieces() {
        guard !hasFramed, !isWorld else { return }
        let coordinates = artworks.compactMap(\.coordinate)
        guard let first = coordinates.first else { return }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(0.01, (maxLat - minLat) * 1.6)),
                                    longitudeDelta: min(350, max(0.01, (maxLon - minLon) * 1.6)))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Tapping a cluster zooms into its cell.
    private func zoom(into center: CLLocationCoordinate2D) {
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        withAnimation {
            position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta / 4,
                                                                                         longitudeDelta: span.longitudeDelta / 4)))
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

/// Loading, empty and error states of the world map, at the bottom so the map stays usable.
struct WorldStatusBanner: View {
    let model: ExploreModel

    var body: some View {
        Group {
            if let error = model.error {
                HStack(spacing: 10) {
                    Text(OnlineMessage.text(for: error)).font(.footnote)
                    Button("Try again") { model.reload() }.font(.footnote.weight(.semibold))
                }
            } else if model.isLoading {
                ProgressView().controlSize(.small)
            } else if model.hasLoaded, model.posts.isEmpty {
                Text("No public pieces here yet.").font(.footnote)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 100)
        .opacity(model.error != nil || model.isLoading || (model.hasLoaded && model.posts.isEmpty) ? 1 : 0)
    }
}
