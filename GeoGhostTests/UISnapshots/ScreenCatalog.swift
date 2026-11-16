import SwiftData
import SwiftUI
@testable import GeoGhost

/// How to put each `screen.state` of ui/screen.yaml on screen from its fixture.
/// Every state that screen.yaml snapshots needs an entry here, and the other way round
/// (UISnapshotTests checks both).
@MainActor
enum ScreenCatalog {
    typealias Builder = @MainActor (UIFixture) -> AnyView

    static let entries: [String: Builder] = [
        "collection.empty": { _ in AnyView(CollectionView()) },
        "collection.typical": { _ in AnyView(CollectionView()) },

        "artwork_detail.no_location": { f in pushed(ArtworkDetailView(artwork: f.artwork("ghost-1"))) },

        "edit_artwork.in_series": { f in AnyView(EditArtworkSheet(artwork: f.artwork("cat-1"))) },

        "series_list.empty": { _ in AnyView(SeriesListView()) },
        "series_list.typical": { _ in AnyView(SeriesListView()) },

        "series_detail.no_location": { f in pushed(SeriesDetailView(series: f.series("ghost"))) },

        "share_card.field_note": { f in shareCard(f, .fieldNote) },
        "share_card.polaroid": { f in shareCard(f, .polaroid) },
        "share_card.poster": { f in shareCard(f, .poster) },
        "share_card.minimal": { f in shareCard(f, .minimal) },

        "publish_status.unpublished": { f in publishStatus(f, .unpublished) },
        "publish_status.uploading": { f in publishStatus(f, .uploading) },
        "publish_status.pending": { f in publishStatus(f, .pending) },
        "publish_status.published": { f in publishStatus(f, .published) },
        "publish_status.re_review": { f in publishStatus(f, .reReview) },
        "publish_status.rejected": { f in publishStatus(f, .rejected) },

        "profile_setup.first_time": { _ in AnyView(ProfileSetupSheet(state: online)) },

        "report.form": { _ in AnyView(ReportSheet(post: UIOnlineFixture.post, state: online)) },

        "feedback.empty": { _ in AnyView(FeedbackView()) },
    ]

    /// What every screen gets from the app around it.
    static func host(_ key: String, fixture: UIFixture) -> AnyView? {
        guard let builder = entries[key] else { return nil }
        return AnyView(builder(fixture)
            .modelContainer(fixture.container)
            .environment(services)
            .tint(Theme.accent))
    }

    // MARK: - Shared

    /// One set of services for the whole run: online features on, backed by the offline fixture.
    private static let online = UIOnlineFixture.makeState()
    private static let services = AppServices(onlineState: online)

    /// A screen that is reached by pushing onto a navigation stack.
    private static func pushed(_ view: some View) -> AnyView {
        AnyView(NavigationStack { view })
    }

    /// A part of a screen, shown alone on the app's background.
    private static func component(_ view: some View) -> AnyView {
        AnyView(view.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(PaperBackground()))
    }

    private static func shareCard(_ fixture: UIFixture, _ style: ShareCardStyle) -> AnyView {
        let content = ShareCardContent(artwork: fixture.artwork("cat-1"), sticker: fixture.sticker("cat-1"))
        return component(ShareCardView(content: content, style: style, showsCredit: true)
            .frame(width: ShareCardView.size.width, height: ShareCardView.size.height))
    }

    private static func publishStatus(_ fixture: UIFixture, _ state: PublishState) -> AnyView {
        let artwork = fixture.artwork("poster-1")
        artwork.publishState = state
        if state.hasRemoteCopy { artwork.remotePostID = UIFixtures.id(post: 1) }
        if state == .published || state == .reReview { artwork.publishedAt = UIFixtures.date("2026-07-02T08:00:00") }
        return component(PublishStatusCard(artwork: artwork, state: online))
    }
}
