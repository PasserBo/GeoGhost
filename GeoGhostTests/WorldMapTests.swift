import CoreLocation
import MapKit
import XCTest
@testable import GeoGhost

private func post(_ n: Int, _ lat: Double, _ lng: Double, daysAgo: Double = 0, cellCount: Int = 1, author: Int = 1) -> ExplorePost {
    ExplorePost(id: UUID(uuidString: String(format: "D0000000-0000-4000-8000-%012d", n))!,
                authorId: UUID(uuidString: String(format: "E0000000-0000-4000-8000-%012d", author))!,
                authorNickname: "hunter", kind: "sticker", lat: lat, lng: lng, locality: "杉並区", countryCode: "JP",
                capturedOn: "2026-06-21", width: 600, height: 600, imageKey: "a.png", thumbKey: "a.png", likeCount: 0,
                publishedAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), cellCount: cellCount)
}

private func region(_ lat: Double, _ lng: Double, span: Double) -> MKCoordinateRegion {
    MKCoordinateRegion(center: .init(latitude: lat, longitude: lng), span: .init(latitudeDelta: span, longitudeDelta: span))
}

final class WorldPinLayoutTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)

    func testPiecesInOneSpotStandBehindTheNewest() {
        // Three within a block of each other and one across town, seen at city scale.
        let posts = [post(1, 35.7023, 139.6497), post(2, 35.7024, 139.6499, daysAgo: 1), post(3, 35.7021, 139.6495, daysAgo: 2),
                     post(4, 35.6614, 139.7680, daysAgo: 3)]
        let groups = WorldPinLayout.arrange(posts, region: region(35.68, 139.70, span: 0.2), size: size)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].representative.id, posts[0].id, "The newest stands for its spot")
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0].members.map(\.id), [posts[0].id, posts[1].id, posts[2].id])
        XCTAssertEqual(groups[1].count, 1)
        XCTAssertTrue(groups.allSatisfy { $0.style == .thumbnail })
    }

    func testZoomingInSeparatesThem() {
        let posts = [post(1, 35.7023, 139.6497), post(2, 35.7043, 139.6517, daysAgo: 1)]
        XCTAssertEqual(WorldPinLayout.arrange(posts, region: region(35.703, 139.650, span: 0.2), size: size).count, 1)
        XCTAssertEqual(WorldPinLayout.arrange(posts, region: region(35.703, 139.650, span: 0.01), size: size).count, 2)
    }

    func testOnlyTheNewestGetThumbnails() {
        // A row of pieces far enough apart not to group.
        let posts = (0..<8).map { post($0 + 1, 35.60 + Double($0) * 0.02, 139.70, daysAgo: Double($0)) }
        let groups = WorldPinLayout.arrange(posts, region: region(35.67, 139.70, span: 0.2), size: size, maxThumbnails: 5)
        XCTAssertEqual(groups.count, 8)
        XCTAssertEqual(groups.filter { $0.style == .thumbnail }.map(\.id), posts.prefix(5).map(\.id))
        XCTAssertEqual(groups.filter { $0.style == .dot }.count, 3)
    }

    func testPiecesOutOfViewAreLeftOut() {
        let posts = [post(1, 35.70, 139.65), post(2, 34.70, 135.50)]
        let groups = WorldPinLayout.arrange(posts, region: region(35.70, 139.65, span: 0.1), size: size)
        XCTAssertEqual(groups.map(\.id), [posts[0].id])
    }

    func testAServerCellCountsForAllItStandsFor() {
        let groups = WorldPinLayout.arrange([post(1, 35.70, 139.65, cellCount: 14)], region: region(35.70, 139.65, span: 1), size: size)
        XCTAssertEqual(groups.first?.count, 14)
        XCTAssertEqual(groups.first?.isFullyKnown, false)
    }

    func testProjectionPutsTheCentreInTheMiddle() {
        let projection = WorldPinLayout.Projection(region: region(35.70, 139.65, span: 0.1), size: size)!
        let centre = projection.point(for: .init(latitude: 35.70, longitude: 139.65))
        XCTAssertEqual(centre.x, 200, accuracy: 0.5)
        XCTAssertEqual(centre.y, 400, accuracy: 0.5)
        XCTAssertEqual(projection.point(for: .init(latitude: 35.75, longitude: 139.65)).y, 0, accuracy: 1)
    }
}

final class WorldCameraTests: XCTestCase {
    private let tokyo = [post(1, 35.7023, 139.6497), post(2, 35.6614, 139.6680, daysAgo: 1), post(3, 35.6190, 139.7280, daysAgo: 2)]
    private let osaka = [post(4, 34.7077, 135.5058, daysAgo: 3)]

    func testOpensOnPiecesNearWhereTheUserCollects() {
        let opening = WorldCamera.opening(posts: tokyo + osaka, anchor: .init(latitude: 34.70, longitude: 135.50))
        XCTAssertEqual(opening?.isNearUser, true)
        XCTAssertEqual(opening?.region.center.latitude ?? 0, 34.7077, accuracy: 0.001)
        XCTAssertEqual(opening?.region.span.latitudeDelta, WorldCamera.minimumSpan, "One piece: a few blocks, not a point")
    }

    func testOpensOnTheBusiestAreaWhenNothingIsNear() {
        let berlin = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.40)
        for anchor in [berlin, nil] {
            let opening = WorldCamera.opening(posts: osaka + tokyo, anchor: anchor)
            XCTAssertEqual(opening?.isNearUser, false)
            XCTAssertEqual(opening?.region.center.latitude ?? 0, (35.7023 + 35.6190) / 2, accuracy: 0.001, "Tokyo has three, Osaka one")
        }
    }

    func testNothingPublicNowhereToOpen() {
        XCTAssertNil(WorldCamera.opening(posts: [], anchor: nil))
    }

    func testTravelIsCountedInScreens() {
        let here = region(35.70, 139.65, span: 0.05)
        XCTAssertEqual(WorldCamera.travel(from: here, to: region(35.72, 139.66, span: 0.05), reduceMotion: false), .pan)
        XCTAssertEqual(WorldCamera.travel(from: here, to: region(35.90, 139.65, span: 0.05), reduceMotion: false), .fly)
        XCTAssertEqual(WorldCamera.travel(from: here, to: region(52.52, 13.40, span: 0.05), reduceMotion: false), .cut)
        // The same 0.2° is a fraction of a screen from far out, and several screens close in.
        XCTAssertEqual(WorldCamera.travel(from: region(35.70, 139.65, span: 2), to: region(35.90, 139.65, span: 2), reduceMotion: false), .pan)
        XCTAssertEqual(WorldCamera.travel(from: here, to: region(35.70, 139.65, span: 5), reduceMotion: false), .cut, "A hundredfold zoom")
        XCTAssertEqual(WorldCamera.travel(from: here, to: region(35.72, 139.66, span: 0.05), reduceMotion: true), .cut)
    }
}

final class OwnAreaPromptsTests: XCTestCase {
    private func piece(_ n: Int, _ lat: Double, _ lng: Double, day: Double = 0, state: PublishState = .unpublished, place: String? = "Kreuzberg, Berlin") -> OwnAreaPrompts.Piece {
        OwnAreaPrompts.Piece(id: UUID(uuidString: String(format: "F0000000-0000-4000-8000-%012d", n))!, latitude: lat, longitude: lng,
                             placeName: place, date: Date(timeIntervalSince1970: 1_800_000_000 + day * 86_400), state: state)
    }

    private var berlin: [OwnAreaPrompts.Piece] {
        [piece(1, 52.499, 13.403), piece(2, 52.501, 13.410, day: 1), piece(3, 52.497, 13.420, day: 2)]
    }

    func testPointerNeedsEnoughPiecesAndNothingPublicNear() {
        let tokyo = [post(1, 35.70, 139.65)]
        let pointer = OwnAreaPrompts.pointer(pieces: berlin, posts: tokyo)
        XCTAssertEqual(pointer?.pieceCount, 3)
        XCTAssertEqual(pointer?.placeName, "Berlin")
        XCTAssertNil(OwnAreaPrompts.pointer(pieces: Array(berlin.prefix(2)), posts: tokyo), "Two pieces are not enough")
        XCTAssertNil(OwnAreaPrompts.pointer(pieces: berlin, posts: tokyo + [post(2, 52.52, 13.40)]), "Someone already shared nearby")
        XCTAssertNil(OwnAreaPrompts.pointer(pieces: [], posts: tokyo))
    }

    func testPointerCountsOnlyUnsharedPiecesAroundTheLatestOne() {
        let pieces = berlin + [piece(4, 52.498, 13.405, day: 3, state: .published), piece(5, 48.85, 2.35, day: -5)]
        // The latest piece is in Berlin; the Paris one and the published one don't count.
        XCTAssertEqual(OwnAreaPrompts.pointer(pieces: pieces, posts: [])?.pieceCount, 3)
    }

    func testInvitationOnlyWhereTheViewIsEmptyAndTheUserHasPieces() {
        let view = region(52.50, 13.41, span: 0.1)
        XCTAssertEqual(OwnAreaPrompts.invitation(pieces: berlin, publicCount: 0, region: view),
                       .share([berlin[2].id, berlin[1].id, berlin[0].id]), "Newest first")
        XCTAssertNil(OwnAreaPrompts.invitation(pieces: berlin, publicCount: 1, region: view))
        XCTAssertNil(OwnAreaPrompts.invitation(pieces: berlin, publicCount: 0, region: region(52.50, 13.41, span: 2)), "Too far out")
        XCTAssertNil(OwnAreaPrompts.invitation(pieces: berlin, publicCount: 0, region: region(48.85, 2.35, span: 0.1)), "No pieces of theirs here")
    }

    func testInvitationSaysWhenEverythingIsInReview() {
        let waiting = [piece(1, 52.499, 13.403, state: .pending), piece(2, 52.501, 13.410, state: .uploading), piece(3, 52.50, 13.41, state: .rejected)]
        XCTAssertEqual(OwnAreaPrompts.invitation(pieces: waiting, publicCount: 0, region: region(52.50, 13.41, span: 0.1)), .inReview(2))
    }

    func testClosingThePointerQuietsItForAWeekThenForGood() {
        let pointer = OwnAreaPrompts.pointer(pieces: berlin, posts: [])!
        var memory = OwnAreaPrompts.PointerMemory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(memory.allows(pointer, now: start))
        memory.dismiss(pointer, now: start)
        XCTAssertFalse(memory.allows(pointer, now: start.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(memory.allows(pointer, now: start.addingTimeInterval(8 * 86_400)))
        memory.dismiss(pointer, now: start.addingTimeInterval(8 * 86_400))
        memory.dismiss(pointer, now: start.addingTimeInterval(16 * 86_400))
        XCTAssertFalse(memory.allows(pointer, now: start.addingTimeInterval(400 * 86_400)), "Three times: not again")
        let more = OwnAreaPrompts.pointer(pieces: berlin + [piece(9, 52.50, 13.41, day: 30)], posts: [])!
        XCTAssertTrue(memory.allows(more, now: start.addingTimeInterval(400 * 86_400)), "Until they collect more there")
    }

    func testMemorySurvivesARoundTrip() {
        let defaults = UserDefaults(suiteName: "OwnAreaPromptsTests")!
        defaults.removePersistentDomain(forName: "OwnAreaPromptsTests")
        var memory = OwnAreaPrompts.PointerMemory()
        memory.dismiss(OwnAreaPrompts.pointer(pieces: berlin, posts: [])!, now: Date(timeIntervalSince1970: 1_800_000_000))
        memory.save(to: defaults)
        XCTAssertEqual(OwnAreaPrompts.PointerMemory.load(from: defaults), memory)
    }
}

@MainActor
final class WorldFeedTests: XCTestCase {
    private func storage() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "world-feed-\(UUID().uuidString).json")
    }

    func testLoadsNewestFirstAndRemembersOnDisk() async {
        let url = storage()
        let feed = WorldFeed(fetch: { [post(1, 35.7, 139.6, daysAgo: 2), post(2, 35.7, 139.6)] }, storage: url)
        XCTAssertFalse(feed.hasContent)
        feed.refresh()
        await feed.settle()
        XCTAssertEqual(feed.phase, .loaded)
        XCTAssertEqual(feed.posts.map(\.id), [post(2, 0, 0).id, post(1, 0, 0).id])
        XCTAssertTrue(feed.isComplete)

        // The next launch, offline: what was seen last is there at once.
        let later = WorldFeed(fetch: { throw OnlineError.offline }, storage: url)
        XCTAssertTrue(later.hasContent)
        XCTAssertTrue(later.isFromDisk)
        XCTAssertEqual(later.posts.count, 2)
        later.refresh()
        await later.settle()
        XCTAssertEqual(later.phase, .failed(.offline))
        XCTAssertEqual(later.posts.count, 2, "A failed refresh keeps what was remembered")
    }

    func testAFullPageMeansThereMayBeMore() async {
        let feed = WorldFeed(fetch: { (0..<WorldFeed.limit).map { post($0 + 1, 35.7, 139.6) } }, storage: nil)
        feed.refresh()
        await feed.settle()
        XCTAssertFalse(feed.isComplete)
    }

    func testDoesNotAskAgainWhileFresh() async {
        actor Counter { var n = 0; func bump() -> Int { n += 1; return n } }
        let counter = Counter()
        let feed = WorldFeed(fetch: { _ = await counter.bump(); return [] }, storage: nil)
        feed.refreshIfNeeded()
        await feed.settle()
        feed.refreshIfNeeded()
        await feed.settle()
        let calls = await counter.n
        XCTAssertEqual(calls, 1)
    }

    func testAReportedPieceLeavesAtOnce() async {
        let feed = WorldFeed(fetch: { [post(1, 35.7, 139.6), post(2, 35.7, 139.6, author: 2)] }, storage: nil)
        feed.refresh()
        await feed.settle()
        feed.remove { $0.id == post(1, 0, 0).id }
        XCTAssertEqual(feed.posts.map(\.id), [post(2, 0, 0).id])
    }
}
