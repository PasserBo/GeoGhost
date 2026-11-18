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

    private static func shareCard(_ context: Context, _ style: ShareCardStyle) -> AnyView {
        let content = ShareCardContent(artwork: context.fixture.artwork("cat-1"), sticker: context.fixture.sticker("cat-1"))
        return component(ShareCardView(content: content, style: style, showsCredit: true)
            .frame(width: ShareCardView.size.width, height: ShareCardView.size.height))
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
