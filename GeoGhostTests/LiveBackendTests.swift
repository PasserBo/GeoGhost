import CoreGraphics
import SwiftData
import XCTest
@testable import GeoGhost

/// The real client against the real backend in Config/Online.xcconfig. Skipped unless asked for:
///
///   TEST_RUNNER_GG_LIVE_TESTS=1 xcodebuild test … -only-testing:GeoGhostTests/LiveBackendTests
///
/// Uses a throwaway guest kept in memory (never the Keychain) and deletes it at the end.
@MainActor
final class LiveBackendTests: XCTestCase {
    private final class MemoryStore: SessionStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var session: AuthSession?
        private var expired = false
        func load() -> AuthSession? { lock.withLock { session } }
        func save(_ session: AuthSession?) { lock.withLock { self.session = session } }
        func loadExpired() -> Bool { lock.withLock { expired } }
        func saveExpired(_ expired: Bool) { lock.withLock { self.expired = expired } }
    }

    func testGuestPublishesReviewsRetractsAndDeletes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GG_LIVE_TESTS"] == "1", "live backend tests are opt-in")
        let config = try XCTUnwrap(OnlineConfig.current, "Config/Online.xcconfig is empty")
        let identity = OnlineSession(auth: SupabaseAuthClient(config: config), store: MemoryStore())
        let services = OnlineServices(config: config, identity: identity, database: PostgrestClient(config: config, identity: identity))
        let container = try GeoGhostSchema.makeContainer(inMemory: true)
        let publisher = ArtworkPublisher(backend: services.publishing, context: container.mainContext, loadCutout: { _, _ in
            let ctx = CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 3200,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 100, y: 50, width: 600, height: 400))
            return ctx.makeImage()
        })

        let artwork = Artwork(kind: .sticker)
        artwork.latitude = 35.659_49
        artwork.longitude = 139.700_55
        artwork.localityName = "Shibuya"
        artwork.countryCode = "JP"
        container.mainContext.insert(artwork)

        do {
            // No browsing identity is created by reading.
            let none = try await identity.existingAccessToken()
            XCTAssertNil(none)

            // Publishing first needs a nickname and the rules.
            do {
                try await publisher.publish(artwork)
                XCTFail("expected profile_required")
            } catch {
                XCTAssertEqual(error as? OnlineError, .refused(.profileRequired))
            }
            XCTAssertEqual(artwork.publishState, .unpublished)
            let noProfile = try await services.account.ownProfile()
            XCTAssertNil(noProfile)

            let profile = try await services.account.saveProfile(nickname: " live test ", termsVersion: 1)
            XCTAssertEqual(profile.nickname, "live test")
            let own = try await services.account.ownProfile()
            XCTAssertEqual(own?.termsVersion, 1)

            let state = try await publisher.publish(artwork)
            XCTAssertEqual(state, .pending)
            let quota = try await services.publishing.quota()
            XCTAssertEqual(quota.dayUsed, 1)

            try await publisher.refreshStates([artwork])
            XCTAssertEqual(artwork.publishState, .pending)

            try await publisher.retract(artwork)
            XCTAssertEqual(artwork.publishState, .unpublished)
            let afterRetract = try await services.publishing.quota()
            XCTAssertEqual(afterRetract.dayUsed, 1, "retracting does not refund quota")
        } catch {
            try? await services.account.deleteMyOnlineData()
            throw error
        }

        try await services.account.deleteMyOnlineData()
        let user = await identity.userID
        XCTAssertNil(user)
    }
}
