import MapKit
import SwiftData
import SwiftUI

/// The world map: everyone's public pieces, opened where there is something to see, with a strip
/// of cards that always shows the piece marked on the map (spec: explore-map).
struct WorldMapView: View {
    let feed: WorldFeed
    let online: OnlineServices
    let state: OnlineState?

    @Query private var artworks: [Artwork]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion?
    /// The opening view was set from what is public, so it isn't decided again.
    @State private var hasOpened: Bool
    /// The user moved the map themselves; from then on the camera only moves when they ask.
    @State private var userMovedMap = false
    /// Camera changes this view started and hasn't seen finish yet.
    @State private var ownMoves = 0
    @State private var sawFirstCamera = false
    @State private var mapSize: CGSize = .zero
    @State private var groups: [WorldPinLayout.Group] = []
    @State private var explore: ExploreModel?
    @State private var scope: WorldStripScope = .latest
    @State private var scopedPosts: [ExplorePost] = []
    /// The rest of a pin's pieces are being fetched.
    @State private var scopedLoading = false
    @State private var showAll = false
    @State private var focusedID: UUID?
    /// The focus was set by tapping the map, so the camera needn't follow it.
    @State private var focusCameFromMap = false
    @State private var regionWhenScoped: MKCoordinateRegion?
    @State private var openedPost: ExplorePost?
    @State private var pointer: OwnAreaPrompts.Pointer?
    @State private var invitation: OwnAreaPrompts.Invitation?
    @State private var dismissedAreas: Set<String> = []
    @State private var showPicker = false
    /// The permission was already given (while capturing), so the map may show where the user is.
    /// The map draws it on the device; this view never reads the coordinate.
    @State private var showUserLocation = false
    @State private var publishing: Artwork?

    /// The pointer appears at most once per launch.
    @MainActor private static var pointerShownThisLaunch = false
    private static let cameraKey = "worldMapCamera"
    /// The height the map leaves clear for the strip.
    private static let stripBand: CGFloat = 136

    /// `opening` overrides where the map starts (UI snapshots open on a known area).
    init(feed: WorldFeed, online: OnlineServices, state: OnlineState?, anchor: CLLocationCoordinate2D?, opening: MapCameraPosition? = nil) {
        self.feed = feed
        self.online = online
        self.state = state
        if let opening {
            _position = State(initialValue: opening)
            _hasOpened = State(initialValue: true)
        } else if feed.hasContent, let decided = WorldCamera.opening(posts: feed.posts, anchor: anchor) {
            // Already known, fresh or remembered: the map appears there, with no loading state.
            _position = State(initialValue: .region(decided.region))
            _hasOpened = State(initialValue: true)
        } else {
            // Not known yet: somewhere familiar meanwhile.
            let fallback = Self.savedCamera() ?? anchor.map {
                MKCoordinateRegion(center: $0, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            }
            _position = State(initialValue: fallback.map(MapCameraPosition.region) ?? .automatic)
            _hasOpened = State(initialValue: false)
        }
    }

    var body: some View {
        GeometryReader { geometry in
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if showUserLocation { UserAnnotation() }
                ForEach(groups) { group in
                    Annotation("", coordinate: group.coordinate) {
                        Group {
                            if group.style == .dot {
                                WorldDotPin(kind: group.representative.artworkKind, isSelected: isSelected(group))
                            } else {
                                WorldGroupPin(group: group, config: online.config, isSelected: isSelected(group))
                            }
                        }
                        .onTapGesture { select(group) }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            // Only with the permission in hand, so the button can never be what asks for it.
            .mapControls { if showUserLocation { MapUserLocationButton() } }
            .onMapCameraChange(frequency: .onEnd) { context in
                mapSize = geometry.size
                cameraSettled(context.region, proxy: proxy)
            }
            .onChange(of: candidates) { regroup(proxy: proxy) }
        }
        }
        // The map keeps a fixed band clear at the bottom whatever the strip is showing. If the band
        // followed the strip's height, a change of content would change what the map shows, which
        // changes the content again, without end.
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Self.stripBand) }
        .overlay(alignment: .bottom) { strip.padding(.horizontal, 10).padding(.bottom, 8) }
        .overlay(alignment: .top) {
            if let content = topNotice {
                WorldTopNotice(content: content, onRetry: retry, onPointer: goToOwnArea, onDismissPointer: dismissPointer)
                    // Clear of the map's own controls in the top-right corner.
                    .padding(.leading, 12).padding(.trailing, 60).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: topNotice)
        .onAppear { showUserLocation = CLLocationManager().authorizationStatus == .authorizedWhenInUse }
        .task { await open() }
        .task(id: pointerInputs) { await considerPointer() }
        .onChange(of: focusedID) { _, id in followFocus(id) }
        .onChange(of: feed.posts) { refreshScopedPosts() }
        .onReceive(NotificationCenter.default.publisher(for: .onlineBlocksChanged)) { note in
            if let author = note.object as? UUID {
                feed.remove { $0.authorId == author }
                explore?.authorBlocked(author)
            } else {
                feed.refresh()
                explore?.invalidate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onlinePostReported)) { note in
            guard let post = note.object as? UUID else { return }
            feed.remove { $0.id == post }
            scopedPosts.removeAll { $0.id == post }
            if scope != .latest, scopedPosts.isEmpty { backToLatest() }
            explore?.postReported(post)
        }
        .sheet(item: $openedPost) { post in
            RemotePostSheet(post: post, config: online.config, state: state)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAll) {
            WorldPostGrid(scope: scope, posts: scopedPosts, isLoading: scopedLoading, config: online.config, state: state, onOpen: focusFromGrid)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPicker) {
            OwnPiecesPicker(pieces: invitedPieces) { artwork in
                showPicker = false
                publishing = artwork
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $publishing) { artwork in
            if let state { PublishSheet(artwork: artwork, state: state) }
        }
    }

    // MARK: What is on the map

    /// Everything that could get a pin. While the feed holds every public piece, that is the feed
    /// itself and the map never has to ask again; once there are more, the server answers per view.
    private var candidates: [ExplorePost] {
        feed.isComplete ? feed.posts : (explore?.posts ?? [])
    }

    private func regroup(proxy: MapProxy) {
        guard visibleRegion != nil else { return }
        groups = WorldPinLayout.arrange(candidates, size: mapSize) { proxy.convert($0, to: .local) }
        evaluateInvitation()
    }

    private func isSelected(_ group: WorldPinLayout.Group) -> Bool {
        guard let focusedID else { return false }
        return group.members.contains { $0.id == focusedID }
    }

    // MARK: Camera

    private func cameraSettled(_ region: MKCoordinateRegion, proxy: MapProxy) {
        // The map reports again whenever it is redrawn; only a real change is worth acting on.
        if let last = visibleRegion, Self.isSame(last, region), mapSize != .zero, !groups.isEmpty || candidates.isEmpty { return }
        visibleRegion = region
        Self.saveCamera(region)
        if !sawFirstCamera {
            sawFirstCamera = true
        } else if ownMoves > 0 {
            ownMoves -= 1
        } else {
            userMovedMap = true
        }
        if !feed.isComplete {
            if explore == nil { explore = ExploreModel(client: ExploreClient(services: online)) }
            explore?.regionChanged(region)
        }
        regroup(proxy: proxy)
    }

    /// Moves the camera the way the distance calls for: a slide, one longer move, or a cut.
    private func move(to target: MKCoordinateRegion) {
        let travel = visibleRegion.map { WorldCamera.travel(from: $0, to: target, reduceMotion: reduceMotion) } ?? .cut
        ownMoves += 1
        if travel == .cut {
            position = .region(target)
        } else {
            withAnimation(.easeInOut(duration: travel.duration)) { position = .region(target) }
        }
    }

    /// Waits a little for the feed when the map opened before it arrived, then goes to what it
    /// decides — unless the user has already taken the map somewhere.
    private func open() async {
        feed.refreshIfNeeded()
        guard !hasOpened else { return }
        for _ in 0..<30 where !feed.hasContent {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled, !hasOpened else { return }
        hasOpened = true
        guard feed.hasContent, !userMovedMap, let decided = WorldCamera.opening(posts: feed.posts, anchor: anchor?.coordinate) else { return }
        move(to: decided.region)
    }

    private static func isSame(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        let tolerance = max(a.span.latitudeDelta, 1e-6) * 0.002
        return abs(a.center.latitude - b.center.latitude) < tolerance && abs(a.center.longitude - b.center.longitude) < tolerance
            && abs(a.span.latitudeDelta - b.span.latitudeDelta) < tolerance && abs(a.span.longitudeDelta - b.span.longitudeDelta) < tolerance
    }

    private static func savedCamera() -> MKCoordinateRegion? {
        guard let v = UserDefaults.standard.array(forKey: cameraKey) as? [Double], v.count == 4,
              CLLocationCoordinate2DIsValid(.init(latitude: v[0], longitude: v[1])), v[2] > 0, v[3] > 0 else { return nil }
        return MKCoordinateRegion(center: .init(latitude: v[0], longitude: v[1]), span: .init(latitudeDelta: v[2], longitudeDelta: v[3]))
    }

    private static func saveCamera(_ region: MKCoordinateRegion) {
        UserDefaults.standard.set([region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta],
                                  forKey: cameraKey)
    }

    // MARK: Strip

    private var stripPosts: [ExplorePost] {
        scope == .latest ? Array(feed.posts.prefix(30)) : scopedPosts
    }

    private var publicCountInView: Int { groups.reduce(0) { $0 + $1.count } }
    /// The view has been loaded and holds no public piece.
    private var isEmptyHere: Bool {
        guard visibleRegion != nil, groups.isEmpty else { return false }
        return feed.isComplete ? feed.hasContent : (explore?.hasLoaded ?? false) && !(explore?.isLoading ?? true)
    }

    @ViewBuilder private var strip: some View {
        if isEmptyHere, scope == .latest {
            WorldEmptyArea(invitation: invitation, pieces: invitedPieces, hasPiecesElsewhere: !feed.posts.isEmpty,
                           onShare: { showPicker = true }, onDismiss: dismissInvitation, onNearest: goToNearest)
        } else {
            WorldStrip(scope: scope, posts: stripPosts, isLoading: feed.phase == .loading || feed.phase == .idle,
                       config: online.config, offersThisArea: offersThisArea, focusedID: $focusedID,
                       onOpen: { openedPost = $0 }, onBackToLatest: backToLatest, onThisArea: showThisArea, onZoomIn: zoomIntoScope,
                       onSeeAll: scopedCount > WorldStrip.swipeableCount ? { showAll = true } : nil)
        }
    }

    /// Offered once the user has moved the map and there is something public in view.
    private var offersThisArea: Bool { userMovedMap && !groups.isEmpty && scope == .latest }

    /// How many pieces the strip stands for, including those of a pin not fetched yet.
    private var scopedCount: Int {
        if case .group(_, let total) = scope { return max(total, scopedPosts.count) }
        return scope == .area ? scopedPosts.count : 0
    }

    /// A piece was opened from the grid: the strip ends up on it, and the map stays where it is.
    private func focusFromGrid(_ post: ExplorePost) {
        guard post.id != focusedID else { return }
        focusCameFromMap = true
        focusedID = post.id
    }

    private func select(_ group: WorldPinLayout.Group) {
        focusCameFromMap = true
        regionWhenScoped = visibleRegion
        scope = .group(id: group.id, total: group.count)
        scopedPosts = group.members
        focusedID = group.representative.id
        scopedLoading = false
        guard !group.isFullyKnown, let region = visibleRegion else { return }
        // A server cell knows only its newest piece: ask for the rest of that cell.
        let cell = ExploreGrid.cellDegrees(forLatitudeSpan: ExploreBounds(region: region).latitudeSpan)
        guard cell > 0 else { return }
        let lat = (group.coordinate.latitude / cell).rounded(.down) * cell, lng = (group.coordinate.longitude / cell).rounded(.down) * cell
        // Just inside the cell, since the server's range includes both ends.
        let bounds = ExploreBounds(minLat: lat, minLng: lng, maxLat: lat + cell - 1e-9, maxLng: lng + cell - 1e-9)
        let client = ExploreClient(services: online), id = group.id
        scopedLoading = true
        Task {
            let members = try? await client.posts(in: bounds, cellDegrees: 0)
            guard case .group(id, _) = scope else { return }
            scopedLoading = false
            if let members { scopedPosts = members }
        }
    }

    private func backToLatest() {
        scope = .latest
        scopedPosts = []
        scopedLoading = false
        showAll = false
        focusedID = nil
        userMovedMap = false
    }

    private func showThisArea() {
        guard let region = visibleRegion else { return }
        regionWhenScoped = region
        scopedPosts = groups.flatMap(\.members).sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        scope = .area
        scopedLoading = false
        focusCameFromMap = true
        focusedID = scopedPosts.first?.id
    }

    private func zoomIntoScope() {
        guard !scopedPosts.isEmpty else { return }
        move(to: WorldCamera.region(fitting: scopedPosts.map(\.coordinate)))
    }

    /// Keeps the strip's pieces in step with the feed (a reported or blocked piece leaves at once).
    private func refreshScopedPosts() {
        guard scope != .latest else { return }
        let alive = Set(candidates.map(\.id)).union(feed.posts.map(\.id))
        scopedPosts.removeAll { !alive.contains($0.id) && feed.isComplete }
        if scopedPosts.isEmpty { backToLatest() }
    }

    /// The card in front changed by scrolling the strip: bring that piece into view.
    private func followFocus(_ id: UUID?) {
        if focusCameFromMap { focusCameFromMap = false; return }
        guard let id, let post = stripPosts.first(where: { $0.id == id }), let visible = visibleRegion else { return }
        // Already comfortably in view: leave the map alone.
        let inner = MKCoordinateRegion(center: visible.center, span: MKCoordinateSpan(latitudeDelta: visible.span.latitudeDelta * 0.6,
                                                                                    longitudeDelta: visible.span.longitudeDelta * 0.6))
        guard !OwnAreaPrompts.contains(inner, post.coordinate) else { return }
        // Keep the zoom unless the map is too far out to tell pieces apart.
        let span = min(visible.span.latitudeDelta, 0.08)
        let ratio = visible.span.longitudeDelta / max(visible.span.latitudeDelta, 1e-9)
        move(to: MKCoordinateRegion(center: post.coordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * ratio)))
    }

    private func goToNearest() {
        guard let center = visibleRegion?.center,
              let nearest = feed.posts.min(by: { WorldCamera.distance($0.coordinate, center) < WorldCamera.distance($1.coordinate, center) }) else { return }
        let around = feed.posts.filter { WorldCamera.distance($0.coordinate, nearest.coordinate) <= WorldCamera.nearbyMeters }
        move(to: WorldCamera.region(fitting: around.map(\.coordinate)))
    }

    // MARK: Top notice

    private var topNotice: WorldTopNotice.Content? {
        if let notice = state?.appConfig.notice() { return .notice(notice) }
        if case .failed(let error) = feed.phase, !feed.hasContent || !feed.isFromDisk { return .error(OnlineMessage.text(for: error)) }
        if let error = explore?.error { return .error(OnlineMessage.text(for: error)) }
        if let pointer { return .pointer(pointer) }
        return nil
    }

    private func retry() {
        feed.refresh()
        explore?.reload()
    }

    // MARK: Prompts from one's own collection

    private var ownPieces: [OwnAreaPrompts.Piece] { artworks.compactMap(OwnAreaPrompts.Piece.init) }
    private var anchor: OwnAreaPrompts.Piece? { OwnAreaPrompts.anchor(of: ownPieces) }

    private struct PointerInputs: Equatable {
        let hasOpened: Bool
        let postCount: Int
        let pieceCount: Int
    }

    private var pointerInputs: PointerInputs {
        PointerInputs(hasOpened: hasOpened, postCount: feed.posts.count, pieceCount: artworks.count)
    }

    /// Shows the pointer a moment after the opening view has settled, once per launch, when the
    /// user's own area has pieces of theirs and nothing public anywhere near.
    private func considerPointer() async {
        // Only when every public piece is known: otherwise "nothing near" can't be told.
        guard hasOpened, feed.phase == .loaded, feed.isComplete, !Self.pointerShownThisLaunch, pointer == nil,
              let candidate = OwnAreaPrompts.pointer(pieces: ownPieces, posts: feed.posts),
              OwnAreaPrompts.PointerMemory.load().allows(candidate, now: Date()) else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled, !Self.pointerShownThisLaunch else { return }
        Self.pointerShownThisLaunch = true
        pointer = candidate
    }

    private func goToOwnArea() {
        guard let pointer else { return }
        self.pointer = nil
        backToLatest()
        move(to: MKCoordinateRegion(center: pointer.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
    }

    private func dismissPointer() {
        guard let pointer else { return }
        var memory = OwnAreaPrompts.PointerMemory.load()
        memory.dismiss(pointer, now: Date())
        memory.save()
        self.pointer = nil
    }

    /// The area on screen, coarse enough that a small pan is still the same area.
    private func areaKey(_ region: MKCoordinateRegion) -> String {
        String(format: "%.1f,%.1f", region.center.latitude, region.center.longitude)
    }

    /// Works out the invitation for the view once the map has rested a moment, so it doesn't flicker
    /// while the user is still on the way somewhere.
    private func evaluateInvitation() {
        guard let region = visibleRegion, isEmptyHere, !dismissedAreas.contains(areaKey(region)) else {
            invitation = nil
            return
        }
        let candidate = OwnAreaPrompts.invitation(pieces: ownPieces, publicCount: publicCountInView, region: region)
        guard candidate != invitation else { return }
        guard candidate != nil else { invitation = nil; return }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard let now = visibleRegion, areaKey(now) == areaKey(region), isEmptyHere else { return }
            withAnimation(.easeOut(duration: 0.2)) { invitation = candidate }
        }
    }

    private func dismissInvitation() {
        if let region = visibleRegion { dismissedAreas.insert(areaKey(region)) }
        invitation = nil
    }

    /// The user's pieces the invitation is about, newest first.
    private var invitedPieces: [Artwork] {
        guard case .share(let ids) = invitation else { return [] }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return artworks.filter { order[$0.id] != nil }.sorted { order[$0.id]! < order[$1.id]! }
    }
}
