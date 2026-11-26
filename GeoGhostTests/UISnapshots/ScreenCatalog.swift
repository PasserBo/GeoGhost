import MapKit
import SwiftData
import SwiftUI
@testable import GeoGhost

/// How to put each `screen.state` of ui/screen.yaml on screen from its fixture.
/// Every state that screen.yaml snapshots needs an entry here, and the other way round
/// (UISnapshotTests checks both).
@MainActor
enum ScreenCatalog {
    /// What an entry builds from: the fixture's data and a fresh set of app services, with online
    /// features on and answered by `UIOnlineFixture`.
    struct Context {
        let fixture: UIFixture
        let online: OnlineState
        let services: AppServices
    }

    typealias Builder = @MainActor (Context) async -> AnyView

    static let entries: [String: Builder] = [
        "collection.empty": { _ in AnyView(CollectionView()) },
        "collection.typical": { _ in AnyView(CollectionView()) },
        "collection.filtered_empty": { _ in AnyView(CollectionView(kindFilter: .poster, favoritesOnly: true)) },
        "collection.search_no_results": { _ in AnyView(CollectionView(searchText: "skateboard")) },

        "artwork_detail.no_location": { c in pushed(ArtworkDetailView(artwork: c.fixture.artwork("ghost-1"))) },
        "artwork_detail.with_location": { c in pushed(ArtworkDetailView(artwork: c.fixture.artwork("cat-1"))) },

        "edit_artwork.in_series": { c in AnyView(EditArtworkSheet(artwork: c.fixture.artwork("cat-1"))) },

        "series_list.empty": { _ in AnyView(SeriesListView()) },
        "series_list.typical": { _ in AnyView(SeriesListView()) },

        "series_detail.no_location": { c in pushed(SeriesDetailView(series: c.fixture.series("ghost"))) },
        "series_detail.with_route": { c in pushed(SeriesDetailView(series: c.fixture.series("cat"))) },

        "map.mine": { _ in map(.mine) },
        "map.empty": { _ in map(.mine) },
        "map.world": { _ in map(.world) },

        "world_strip.latest": { _ in worldStrip(.latest, focused: 0) },
        "world_strip.group": { _ in worldStrip(.group(id: UIFixtures.id(post: 1), total: 4), focused: 1) },
        "world_strip.many": { _ in worldStrip(.group(id: UIFixtures.id(post: 1), total: 23), focused: 0, count: 23) },
        "world_post_grid.typical": { c in
            AnyView(WorldPostGrid(scope: .group(id: UIFixtures.id(post: 1), total: 23), posts: worldPosts(23), isLoading: false,
                                  config: UIOnlineFixture.config, state: c.online, onOpen: { _ in }))
        },
        "world_post_grid.loading": { c in
            AnyView(WorldPostGrid(scope: .group(id: UIFixtures.id(post: 1), total: 23), posts: worldPosts(1), isLoading: true,
                                  config: UIOnlineFixture.config, state: c.online, onOpen: { _ in }))
        },
        "world_post_grid.capped": { c in
            AnyView(WorldPostGrid(scope: .group(id: UIFixtures.id(post: 1), total: 340), posts: worldPosts(8), isLoading: false,
                                  config: UIOnlineFixture.config, state: c.online, onOpen: { _ in }))
        },
        "world_strip.loading": { _ in
            component(WorldStrip(scope: .latest, posts: [], isLoading: true, config: UIOnlineFixture.config, offersThisArea: false,
                                 focusedID: .constant(nil), onOpen: { _ in }, onBackToLatest: {}, onThisArea: {}, onZoomIn: {}))
        },

        "world_empty_area.invitation": { c in
            let pieces = ["cat-1", "sticker-2", "graffiti-1", "poster-1"].map { c.fixture.artwork($0) }
            return component(WorldEmptyArea(invitation: .share(pieces.map(\.id)), pieces: pieces, hasPiecesElsewhere: true,
                                            onShare: {}, onDismiss: {}, onNearest: {}))
        },
        "world_empty_area.in_review": { _ in
            component(WorldEmptyArea(invitation: .inReview(2), pieces: [], hasPiecesElsewhere: true, onShare: {}, onDismiss: {}, onNearest: {}))
        },
        "world_empty_area.nothing_of_mine": { _ in
            component(WorldEmptyArea(invitation: nil, pieces: [], hasPiecesElsewhere: true, onShare: {}, onDismiss: {}, onNearest: {}))
        },

        "world_top_notice.pointer": { _ in
            let pointer = OwnAreaPrompts.Pointer(placeName: "杉並区", pieceCount: 12, latitude: 35.70, longitude: 139.65)
            return component(WorldTopNotice(content: .pointer(pointer), onRetry: {}, onPointer: {}, onDismissPointer: {}))
        },
        "world_top_notice.error": { _ in
            component(WorldTopNotice(content: .error(OnlineMessage.text(for: .offline)), onRetry: {}, onPointer: {}, onDismissPointer: {}))
        },

        "remote_post.typical": { c in
            AnyView(RemotePostSheet(post: UIOnlineFixture.post, config: UIOnlineFixture.config, state: c.online))
        },

        "capture.unavailable": { _ in AnyView(CaptureView()) },

        "segmentation_editor.nothing_selected": { _ in
            let model = await analyzedPhoto()
            return AnyView(SegmentationEditorView(model: model))
        },
        "segmentation_editor.selected": { _ in
            // The second appearance shows the same selection; no need to cut it out again.
            if let selectedModel { return AnyView(SegmentationEditorView(model: selectedModel)) }
            let model = await analyzedPhoto()
            // A loop drawn around the cat, as a finger would.
            let loop = (0..<32).map { i -> CGPoint in
                let angle = Double(i) / 32 * 2 * .pi
                return CGPoint(x: 0.5 + 0.36 * cos(angle), y: 0.39 + 0.27 * sin(angle))
            }
            model.lassoEnded(loop)
            // Cutting it out takes about twenty seconds in a debug build, hence the long wait and
            // the reuse below.
            for _ in 0..<1200 where (model.isPicking || !model.hasSelection) && !model.lastPickFailed {
                try? await Task.sleep(for: .milliseconds(50))
            }
            selectedModel = model
            return AnyView(SegmentationEditorView(model: model))
        },

        "manual_crop.typical": { _ in
            AnyView(ManualCropView(image: FixturePicture.photo(), canGoBack: true) { _ in } onBack: {} onCancel: {})
        },

        "save_artwork.typical": { _ in
            let model = await analyzedPhoto()
            model.finishManualCrop(normalizedRect: CGRect(x: 0.17, y: 0.14, width: 0.66, height: 0.50))
            guard let cutout = model.cutout else { return AnyView(Text(verbatim: "The fixture photo could not be cropped")) }
            return AnyView(SaveArtworkSheet(model: model, cutout: cutout) { _ in })
        },

        "share_card.field_note": { c in shareCard(c, .fieldNote) },
        "share_card.polaroid": { c in shareCard(c, .polaroid) },
        "share_card.poster": { c in shareCard(c, .poster) },
        "share_card.minimal": { c in shareCard(c, .minimal) },
        "share_card.tall_sticker": { c in shareCard(c, .fieldNote, picture: tallSticker) },
        "share_card.wide_sticker": { c in shareCard(c, .fieldNote, picture: wideSticker) },

        "series_share_card.distance": { c in seriesCard(c, "cat", .distance) },
        "series_share_card.encounters": { c in seriesCard(c, "cat", .encounters) },
        "series_share_card.tall_sticker": { c in seriesCard(c, "cat", .distance, picture: tallSticker) },
        "series_share_card.wide_sticker": { c in seriesCard(c, "cat", .distance, picture: wideSticker) },
        "series_share_card.no_location": { c in seriesCard(c, "ghost", .encounters) },
        // The two Tokyo sightings alone: close enough for the map to need the country locator.
        "series_share_card.same_city": { c in seriesCard(c, "cat", .encounters, members: 2) },

        "publish_status.unpublished": { c in publishStatus(c, .unpublished) },
        "publish_status.uploading": { c in publishStatus(c, .uploading) },
        "publish_status.pending": { c in publishStatus(c, .pending) },
        "publish_status.published": { c in publishStatus(c, .published) },
        "publish_status.re_review": { c in publishStatus(c, .reReview) },
        "publish_status.rejected": { c in publishStatus(c, .rejected) },

        "publish.ready": { c in AnyView(PublishSheet(artwork: c.fixture.artwork("poster-1"), state: c.online)) },
        "publish.quota_reached": { c in
            UIOnlineFixture.scenario.dayUsed = 5
            return AnyView(PublishSheet(artwork: c.fixture.artwork("poster-1"), state: c.online))
        },

        "profile_setup.first_time": { c in
            UIOnlineFixture.scenario.hasProfile = false
            return AnyView(ProfileSetupSheet(state: c.online))
        },

        "report.form": { c in AnyView(ReportSheet(post: UIOnlineFixture.post, state: c.online)) },
        "report.sent": { c in AnyView(ReportSheet(post: UIOnlineFixture.post, state: c.online, startsSent: true)) },

        "blocked_users.typical": { c in
            UIOnlineFixture.scenario.blockedUsers = 3
            return pushed(BlockedUsersView(state: c.online))
        },
        "blocked_users.empty": { c in pushed(BlockedUsersView(state: c.online)) },

        "settings.typical": { _ in AnyView(SettingsView()) },

        "feedback.empty": { _ in AnyView(FeedbackView()) },
        "feedback.sent": { _ in AnyView(FeedbackView(outcome: .sent)) },

        "paywall.locked": { _ in AnyView(PaywallView()) },
    ]

    /// Builds the screen with what the app would put around it. Each call starts from the default
    /// scenario and its own services, so one screen's server data or loaded profile never reaches the next.
    static func host(_ key: String, fixture: UIFixture) async -> AnyView? {
        guard let builder = entries[key] else { return nil }
        reset()
        let online = UIOnlineFixture.makeState()
        let context = Context(fixture: fixture, online: online, services: AppServices(onlineState: online))
        return AnyView(await builder(context)
            .modelContainer(fixture.container)
            .environment(context.services)
            .tint(Theme.accent))
    }

    /// Puts back everything an entry may have changed outside its own view.
    static func reset() {
        UIOnlineFixture.scenario = UIOnlineFixture.Scenario()
    }

    // MARK: - Shared

    private static var selectedModel: CaptureFlowModel?

    /// A screen that is reached by pushing onto a navigation stack.
    private static func pushed(_ view: some View) -> AnyView {
        AnyView(NavigationStack { view })
    }

    /// A part of a screen, shown alone on the app's background.
    private static func component(_ view: some View) -> AnyView {
        AnyView(view.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(PaperBackground()))
    }

    private static var tallSticker: UIImage { FixturePicture.strip(width: 220, height: 900, hex: "#219E8C") }
    private static var wideSticker: UIImage { FixturePicture.strip(width: 900, height: 220, hex: "#8C5CF5") }

    private static func shareCard(_ context: Context, _ style: ShareCardStyle, picture: UIImage? = nil) -> AnyView {
        let content = ShareCardContent(artwork: context.fixture.artwork("cat-1"), sticker: picture ?? context.fixture.sticker("cat-1"))
        return component(ShareCardView(content: content, style: style, showsCredit: true)
            .frame(width: ShareCardView.size.width, height: ShareCardView.size.height))
    }

    /// A series card over a stand-in map: plain colour with every stop where a real map would put
    /// it, so the route layer is compared without loading map tiles.
    private static func seriesCard(_ context: Context, _ key: String, _ lead: SeriesShareCard.Lead, members count: Int? = nil,
                                   picture: UIImage? = nil) -> AnyView {
        let series = context.fixture.series(key)
        let members = Array(series.members.prefix(count ?? series.members.count))
        let stats = SeriesStats(encounters: members.map { a in
            SeriesStats.Encounter(latitude: a.coordinate?.latitude, longitude: a.coordinate?.longitude, placeName: a.placeName,
                                  localityName: a.localityName, countryCode: a.countryCode, date: a.displayDate)
        })
        let cover = members.last!
        let picture = picture ?? context.fixture.sticker(context.fixture.key(of: cover))
        let content = SeriesCardContent(
            number: key == "cat" ? 1 : 2,
            title: series.title,
            kind: cover.kind,
            picture: picture,
            stats: stats,
            map: standInMap(for: stats, size: SeriesShareCard.mapSize(for: picture, isPhoto: false)),
            countryOutline: CountryOutlines.shared.outline(for: stats.countryCode))
        return component(SeriesShareCard(content: content, lead: lead))
    }

    private static func standInMap(for stats: SeriesStats, size: CGSize) -> RouteMapImage? {
        guard !stats.stops.isEmpty else { return nil }
        let region = RouteMapSnapshotter.region(for: stats.stops.map(\.coordinate))
        // Fit the region into the map's shape the way a map would, longitude squeezed by latitude.
        let squeeze = cos(region.center.latitude * .pi / 180)
        let scale = min(size.width / (region.span.longitudeDelta * squeeze), size.height / region.span.latitudeDelta)
        let points = stats.stops.map { stop in
            CGPoint(x: 0.5 + (stop.longitude - region.center.longitude) * squeeze * scale / size.width,
                    y: 0.5 - (stop.latitude - region.center.latitude) * scale / size.height)
        }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.86, green: 0.89, blue: 0.86, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return RouteMapImage(image: image, size: size, points: points)
    }

    private static func worldPosts(_ count: Int) -> [ExplorePost] {
        let base = UIOnlineFixture.post
        let places = [("杉並区", "sticker", "cat.png"), ("渋谷区", "tag", "ghost.png"), ("千代田区", "graffiti", "star.png")]
        return (0..<count).map { index in
            let place = places[index % places.count]
            return ExplorePost(id: UIFixtures.id(post: index + 1), authorId: base.authorId, authorNickname: base.authorNickname, kind: place.1,
                               lat: base.lat, lng: base.lng, locality: place.0, countryCode: "JP", capturedOn: "2026-06-2\(index % 9 + 1)",
                               width: 600, height: 600, imageKey: place.2, thumbKey: place.2, likeCount: 0, publishedAt: nil, cellCount: 1)
        }
    }

    private static func worldStrip(_ scope: WorldStripScope, focused: Int, count: Int = 3) -> AnyView {
        let posts = worldPosts(count)
        return component(WorldStrip(scope: scope, posts: posts, isLoading: false, config: UIOnlineFixture.config, offersThisArea: scope == .latest,
                                    focusedID: .constant(posts[focused].id), onOpen: { _ in }, onBackToLatest: {}, onThisArea: {}, onZoomIn: {},
                                    onSeeAll: count > WorldStrip.swipeableCount ? {} : nil))
    }

    private static func publishStatus(_ context: Context, _ state: PublishState) -> AnyView {
        let artwork = context.fixture.artwork("poster-1")
        artwork.publishState = state
        if state.hasRemoteCopy { artwork.remotePostID = UIFixtures.id(post: 1) }
        if state == .published || state == .reReview { artwork.publishedAt = UIFixtures.date("2026-07-02T08:00:00") }
        return component(PublishStatusCard(artwork: artwork, state: context.online))
    }

    private static func map(_ mode: ArtMapView.Mode) -> AnyView {
        // Tokyo, where the fixture server's pieces are. One's own pieces frame themselves.
        let tokyo = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.672, longitude: 139.712),
                                       span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22))
        return AnyView(ArtMapView(mode: mode, position: .region(tokyo)))
    }

    /// The capture flow after the fixture photo was taken and analysed, ready for the editor.
    private static func analyzedPhoto() async -> CaptureFlowModel {
        let model = CaptureFlowModel()
        var metadata = CaptureMetadata()
        metadata.capturedAt = UIFixtures.date("2026-08-20T15:30:00")
        metadata.deviceModel = "iPhone 17 Pro"
        model.receiveStoredPhoto(FixturePicture.photoData(), metadata: metadata, alreadySaved: [])
        for _ in 0..<200 where model.stage == .analyzing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return model
    }
}
