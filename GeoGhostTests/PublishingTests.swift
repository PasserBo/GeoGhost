import CoreGraphics
import SwiftData
import XCTest
@testable import GeoGhost

/// A server that behaves like design.md §5–§8: one post per artwork, quota counted per created
/// post, uploads can be made to fail.
private actor FakePublishBackend: PublishBackend {
    var posts: [UUID: (artwork: UUID, status: String)] = [:]
    var drafts: [PostDraft] = []
    var created = 0
    var uploads = 0
    var retracted: [UUID] = []
    var failUploadsWith: OnlineError?
    var refuseCreateWith: OnlineRefusal?
    var trusted = false

    func setFailUploads(_ error: OnlineError?) { failUploadsWith = error }
    func setRefuseCreate(_ refusal: OnlineRefusal?) { refuseCreateWith = refusal }
    func setStatus(_ status: String?, for postID: UUID) {
        if let status { posts[postID]?.status = status } else { posts[postID] = nil }
    }

    func quota() async throws -> PublishQuota {
        PublishQuota(monthUsed: created, monthLimit: 20, dayUsed: created, dayLimit: 5, resetsAt: Date())
    }

    func createPost(_ draft: PostDraft) async throws -> CreatedPost {
        if let refuseCreateWith { throw OnlineError.refused(refuseCreateWith) }
        drafts.append(draft)
        if let existing = posts.first(where: { $0.value.artwork == draft.clientArtworkId && $0.value.status != "removed" }) {
            return CreatedPost(postId: existing.key, status: existing.value.status)
        }
        created += 1
        let id = UUID()
        posts[id] = (draft.clientArtworkId, "uploading")
        return CreatedPost(postId: id, status: "uploading")
    }

    func uploadImages(postID: UUID, images: PublishImageEncoder.Output) async throws -> String {
        uploads += 1
        if let failUploadsWith { throw failUploadsWith }
        let status = trusted ? "public" : "pending"
        posts[postID]?.status = status
        return status
    }

    func retract(postID: UUID) async throws {
        retracted.append(postID)
        posts[postID]?.status = "removed"
    }

    func statuses(of postIDs: [UUID]) async throws -> [UUID: String] {
        var result: [UUID: String] = [:]
        for id in postIDs { if let p = posts[id], p.status != "removed" { result[id] = p.status } }
        return result
    }
}

@MainActor
final class ArtworkPublisherTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var backend: FakePublishBackend!

    override func setUp() async throws {
        container = try GeoGhostSchema.makeContainer(inMemory: true)
        backend = FakePublishBackend()
    }

    nonisolated private static func cutout() -> CGImage {
        let ctx = CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 2400,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 50, width: 400, height: 200))
        return ctx.makeImage()!
    }

    private func publisher() -> ArtworkPublisher {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return ArtworkPublisher(backend: backend, context: context, loadCutout: { _, _ in Self.cutout() }, calendar: calendar)
    }

    private func makeArtwork(located: Bool = true) -> Artwork {
        let artwork = Artwork(kind: .graffiti)
        if located { artwork.latitude = 35.659_49; artwork.longitude = 139.700_55 }
        artwork.localityName = "Shibuya"
        artwork.countryCode = "JP"
        artwork.capturedAt = ISO8601DateFormatter().date(from: "2026-11-12T14:30:00Z")   // 23:30 in Tokyo
        artwork.note = "behind the station, 3rd pole"
        context.insert(artwork)
        return artwork
    }

    func testPublishSendsOnlyPublicFieldsAndRecordsReview() async throws {
        let artwork = makeArtwork()
        let state = try await publisher().publish(artwork)

        XCTAssertEqual(state, .pending)
        XCTAssertEqual(artwork.publishState, .pending)
        XCTAssertEqual(artwork.visibility, .publicShared)
        XCTAssertNotNil(artwork.remotePostID)
        XCTAssertNil(artwork.publishedAt)

        let drafts = await backend.drafts
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.clientArtworkId, artwork.id)
        XCTAssertEqual(draft.kind, "graffiti")
        XCTAssertEqual(draft.lat, 35.659)
        XCTAssertEqual(draft.lng, 139.701)
        XCTAssertEqual(draft.capturedOn, "2026-11-12")
        XCTAssertEqual(draft.locality, "Shibuya")
        XCTAssertEqual(draft.width, 600)
        // The note never leaves the device: PostDraft has no field for it.
        let json = String(decoding: try OnlineHTTP.encoder.encode(draft), as: UTF8.self)
        XCTAssertFalse(json.contains("pole"))
    }

    func testTrustedAuthorIsPublishedAtOnce() async throws {
        await backend.setTrusted()
        let artwork = makeArtwork()
        let state = try await publisher().publish(artwork)
        XCTAssertEqual(state, .published)
        XCTAssertNotNil(artwork.publishedAt)
    }

    func testPieceWithoutLocationCannotBePublished() async {
        let artwork = makeArtwork(located: false)
        do {
            try await publisher().publish(artwork)
            XCTFail("expected noLocation")
        } catch {
            XCTAssertEqual(error as? PublishError, .noLocation)
        }
        let created = await backend.created
        XCTAssertEqual(created, 0)
        XCTAssertEqual(artwork.publishState, .unpublished)
    }

    /// Spec: an interrupted publish shows as unfinished; retrying finishes it and uses quota once.
    func testInterruptedUploadCanBeRetriedWithoutUsingQuotaTwice() async throws {
        let artwork = makeArtwork()
        await backend.setFailUploads(.offline)
        do {
            try await publisher().publish(artwork)
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? OnlineError, .offline)
        }
        XCTAssertEqual(artwork.publishState, .uploading)
        let firstPost = artwork.remotePostID
        XCTAssertNotNil(firstPost)

        await backend.setFailUploads(nil)
        let state = try await publisher().publish(artwork)
        XCTAssertEqual(state, .pending)
        XCTAssertEqual(artwork.remotePostID, firstPost)
        let quota = try await backend.quota()
        XCTAssertEqual(quota.monthUsed, 1)
    }

    func testFinishedUploadWhoseAnswerWasLostIsNotUploadedAgain() async throws {
        let artwork = makeArtwork()
        try await publisher().publish(artwork)
        artwork.publishState = .uploading   // as if the app quit before recording the answer
        artwork.remotePostID = await backend.posts.keys.first
        let state = try await publisher().publish(artwork)
        XCTAssertEqual(state, .pending)
        let uploads = await backend.uploads
        XCTAssertEqual(uploads, 1)
    }

    func testRefusalLeavesPiecePrivate() async {
        let artwork = makeArtwork()
        await backend.setRefuseCreate(.profileRequired)
        do {
            try await publisher().publish(artwork)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? OnlineError, .refused(.profileRequired))
        }
        XCTAssertEqual(artwork.publishState, .unpublished)
        XCTAssertNil(artwork.remotePostID)
    }

    /// Spec: retracting makes the piece private; publishing again is a new post and uses new quota.
    func testRetractThenPublishAgain() async throws {
        let artwork = makeArtwork()
        try await publisher().publish(artwork)
        let first = try XCTUnwrap(artwork.remotePostID)

        try await publisher().retract(artwork)
        XCTAssertEqual(artwork.publishState, .unpublished)
        XCTAssertEqual(artwork.visibility, .privateOnly)
        XCTAssertNil(artwork.remotePostID)
        let retracted = await backend.retracted
        XCTAssertEqual(retracted, [first])

        try await publisher().publish(artwork)
        XCTAssertNotEqual(artwork.remotePostID, first)
        let quota = try await backend.quota()
        XCTAssertEqual(quota.monthUsed, 2)
    }

    func testRetractAllSkipsPrivatePieces() async throws {
        let a = makeArtwork(), b = makeArtwork(), c = makeArtwork()
        try await publisher().publish(a)
        try await publisher().publish(b)
        try await publisher().retractAll([a, b, c])
        XCTAssertEqual([a, b, c].map(\.publishState), [.unpublished, .unpublished, .unpublished])
        let retracted = await backend.retracted
        XCTAssertEqual(retracted.count, 2)
    }

    func testRefreshPicksUpReviewHidingAndDeletion() async throws {
        let approved = makeArtwork(), hidden = makeArtwork(), gone = makeArtwork()
        for artwork in [approved, hidden, gone] { try await publisher().publish(artwork) }
        await backend.setStatus("public", for: try XCTUnwrap(approved.remotePostID))
        await backend.setStatus("hidden", for: try XCTUnwrap(hidden.remotePostID))
        await backend.setStatus(nil, for: try XCTUnwrap(gone.remotePostID))

        try await publisher().refreshStates([approved, hidden, gone])
        XCTAssertEqual(approved.publishState, .published)
        XCTAssertNotNil(approved.publishedAt)
        XCTAssertEqual(hidden.publishState, .rejected)
        XCTAssertEqual(hidden.visibility, .publicShared)
        XCTAssertEqual(gone.publishState, .unpublished)
        XCTAssertNil(gone.remotePostID)
    }

    /// Hidden after reports means back in review, not rejected: the author sees "In review".
    func testPostPutBackIntoReviewAfterReportsIsInReReview() async throws {
        let artwork = makeArtwork()
        try await publisher().publish(artwork)
        let postID = try XCTUnwrap(artwork.remotePostID)
        XCTAssertEqual(artwork.publishState, .pending, "first review")
        await backend.setStatus("public", for: postID)
        try await publisher().refreshStates([artwork])
        XCTAssertEqual(artwork.publishState, .published)

        await backend.setStatus(PublishState.reReviewStatus, for: postID)
        try await publisher().refreshStates([artwork])
        XCTAssertEqual(artwork.publishState, .reReview, "kept apart from a first review")
        XCTAssertEqual(artwork.visibility, .publicShared, "still has a copy on the server to retract")
        XCTAssertNotNil(artwork.publishedAt, "keeps when it was first published")
        XCTAssertEqual(artwork.remotePostID, postID)

        await backend.setStatus("public", for: postID)
        try await publisher().refreshStates([artwork])
        XCTAssertEqual(artwork.publishState, .published)
    }
}

private extension FakePublishBackend {
    func setTrusted() { trusted = true }
}

// MARK: - HTTP shape

final class PublishClientTests: XCTestCase {
    private let config = OnlineConfig(supabaseURL: URL(string: "https://project.supabase.test")!, anonKey: "anon",
                                      apiURL: URL(string: "https://api.test")!, imageBaseURL: URL(string: "https://api.test/v1/images")!)

    override func setUp() {
        OnlineStubProtocol.recorded = []
    }

    /// OnlineServices with a signed-in guest whose session never needs refreshing.
    private func makeClient() -> PublishClient {
        let session = AuthSession(accessToken: "user-token", refreshToken: "r", expiresAt: .distantFuture, userID: UUID(), isAnonymous: true)
        let identity = OnlineSession(auth: SupabaseAuthClient(config: config, session: OnlineStubProtocol.session()),
                                     store: StaticStore(session: session))
        let services = OnlineServices(config: config, identity: identity,
                                      database: PostgrestClient(config: config, identity: identity, session: OnlineStubProtocol.session()))
        return PublishClient(services: services, session: OnlineStubProtocol.session())
    }

    func testUploadSendsTwoHEICParts() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, Data(#"{"status":"pending"}"#.utf8)) }
        let post = UUID()
        let images = PublishImageEncoder.Output(full: Data("FULL".utf8), thumb: Data("THUMB".utf8), fullWidth: 10, fullHeight: 10)
        let status = try await makeClient().uploadImages(postID: post, images: images)
        XCTAssertEqual(status, "pending")

        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.httpMethod, "PUT")
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.test/v1/posts/\(post.uuidString.lowercased())/images")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
        XCTAssertTrue(sent.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: sent.body, as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="full""#) && body.contains("FULL"))
        XCTAssertTrue(body.contains(#"name="thumb""#) && body.contains("THUMB"))
        XCTAssertEqual(body.components(separatedBy: "Content-Type: image/heic").count, 3)
    }

    func testWorkerRefusalsAreMapped() async {
        let cases: [(Int, String, OnlineError)] = [
            (403, "banned", .refused(.banned)), (413, "too_large", .tooLarge),
            (415, "unsupported_media_type", .unsupportedImage), (409, "invalid_status", .conflict),
        ]
        for (status, code, expected) in cases {
            OnlineStubProtocol.handler = { _, _ in (status, Data(#"{"error":"\#(code)","message":"x"}"#.utf8)) }
            let images = PublishImageEncoder.Output(full: Data(), thumb: Data(), fullWidth: 1, fullHeight: 1)
            do {
                _ = try await makeClient().uploadImages(postID: UUID(), images: images)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? OnlineError, expected)
            }
        }
    }

    func testRetractingAPostThatIsAlreadyGoneSucceeds() async throws {
        OnlineStubProtocol.handler = { _, _ in (404, Data(#"{"error":"not_found","message":"x"}"#.utf8)) }
        try await makeClient().retract(postID: UUID())
    }

    func testStatusesQueryAndMapping() async throws {
        let a = UUID(), b = UUID()
        OnlineStubProtocol.handler = { _, _ in
            (200, Data(#"[{"id":"\#(a.uuidString.lowercased())","status":"public"}]"#.utf8))
        }
        let statuses = try await makeClient().statuses(of: [a, b])
        XCTAssertEqual(statuses, [a: "public"])
        let url = try XCTUnwrap(OnlineStubProtocol.recorded.first?.request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "id" }?.value, "in.(\(a.uuidString.lowercased()),\(b.uuidString.lowercased()))")
        XCTAssertEqual(query.first { $0.name == "select" }?.value, "id,status,published_at")
        XCTAssertEqual(PublishState(serverStatus: statuses[b]), .unpublished)
        XCTAssertEqual(PublishState(serverStatus: "hidden"), .rejected)
    }

    func testPostBackInReviewAfterReportsIsReReview() async throws {
        let first = UUID(), again = UUID(), live = UUID()
        OnlineStubProtocol.handler = { _, _ in
            (200, Data("""
            [{"id":"\(first.uuidString.lowercased())","status":"pending","published_at":null},
             {"id":"\(again.uuidString.lowercased())","status":"pending","published_at":"2026-11-01T00:00:00+00:00"},
             {"id":"\(live.uuidString.lowercased())","status":"public","published_at":"2026-11-01T00:00:00+00:00"}]
            """.utf8))
        }
        let statuses = try await makeClient().statuses(of: [first, again, live])
        XCTAssertEqual(PublishState(serverStatus: statuses[first]), .pending)
        XCTAssertEqual(PublishState(serverStatus: statuses[again]), .reReview)
        XCTAssertEqual(PublishState(serverStatus: statuses[live]), .published)
        XCTAssertTrue(PublishState.reReview.hasRemoteCopy)
    }
}

private struct StaticStore: SessionStoring {
    let session: AuthSession
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession?) {}
    func loadExpired() -> Bool { false }
    func saveExpired(_ expired: Bool) {}
}
