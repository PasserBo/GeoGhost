import CoreLocation
import ImageIO
import MapKit
import XCTest
@testable import GeoGhost

/// Answers requests with whatever `handler` returns and records them.
final class OnlineStubProtocol: URLProtocol {
    struct Recorded {
        let request: URLRequest
        let body: Data
    }

    nonisolated(unsafe) static var handler: (URLRequest, Data) -> (Int, Data) = { _, _ in (200, Data("{}".utf8)) }
    nonisolated(unsafe) static var recorded: [Recorded] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnlineStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        Self.recorded.append(Recorded(request: request, body: body))
        let (status, data) = Self.handler(request, body)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private let testConfig = OnlineConfig(supabaseURL: URL(string: "https://project.supabase.test")!, anonKey: "anon-key",
                                      apiURL: URL(string: "https://api.test")!, imageBaseURL: URL(string: "https://api.test/v1/images")!)

private func tokenJSON(access: String = "access-1", refresh: String = "refresh-1", expiresIn: Int = 3600,
                       user: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!) -> Data {
    Data("""
    {"access_token":"\(access)","token_type":"bearer","expires_in":\(expiresIn),"expires_at":0,
     "refresh_token":"\(refresh)","user":{"id":"\(user.uuidString.lowercased())","is_anonymous":true}}
    """.utf8)
}

// MARK: - Config

final class OnlineConfigTests: XCTestCase {
    func testReadsAllKeys() throws {
        let config = try XCTUnwrap(OnlineConfig(info: [
            "GGSupabaseURL": "https://abc.supabase.co", "GGSupabaseAnonKey": "key",
            "GGOnlineAPIURL": "https://api.example.dev", "GGImageBaseURL": "https://api.example.dev/v1/images",
        ]))
        XCTAssertEqual(config.imageURL(key: "posts/x/thumb.heic").absoluteString, "https://api.example.dev/v1/images/posts/x/thumb.heic")
    }

    func testMissingOrUnresolvedValuesDisableOnline() {
        let full: [String: Any] = ["GGSupabaseURL": "https://abc.supabase.co", "GGSupabaseAnonKey": "key",
                                   "GGOnlineAPIURL": "https://api.example.dev", "GGImageBaseURL": "https://img.example.dev"]
        for key in full.keys {
            var info = full
            info[key] = ""
            XCTAssertNil(OnlineConfig(info: info), "empty \(key)")
            info[key] = "$(GG_SOMETHING)"
            XCTAssertNil(OnlineConfig(info: info), "unresolved \(key)")
        }
        XCTAssertNil(OnlineConfig(info: [:]))
    }

    /// Unit tests run inside the app built with an empty Config/Online.xcconfig.
    func testBuildWithoutBackendHasNoOnlineServices() {
        XCTAssertNil(OnlineConfig(info: ["GGSupabaseURL": "", "GGSupabaseAnonKey": "", "GGOnlineAPIURL": "", "GGImageBaseURL": ""]))
    }
}

// MARK: - Keychain

final class KeychainStoreTests: XCTestCase {
    func testSetUpdateReadRemove() throws {
        let store = KeychainStore(service: "com.passerbo.geoghost.tests.\(UUID().uuidString)")
        XCTAssertNil(try store.data(for: "a"))
        try store.set(Data([1, 2]), for: "a")
        XCTAssertEqual(try store.data(for: "a"), Data([1, 2]))
        try store.set(Data([3]), for: "a")
        XCTAssertEqual(try store.data(for: "a"), Data([3]))
        try store.remove("a")
        XCTAssertNil(try store.data(for: "a"))
        try store.remove("a")   // removing a missing item is fine
    }
}

// MARK: - Auth

final class SupabaseAuthClientTests: XCTestCase {
    override func setUp() {
        OnlineStubProtocol.recorded = []
    }

    func testAnonymousSignIn() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, tokenJSON(expiresIn: 3600)) }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let client = SupabaseAuthClient(config: testConfig, session: OnlineStubProtocol.session(), now: { start })
        let session = try await client.signInAnonymously()

        XCTAssertEqual(session.accessToken, "access-1")
        XCTAssertEqual(session.refreshToken, "refresh-1")
        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(3600))
        XCTAssertEqual(session.userID, UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertTrue(session.isAnonymous)

        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.absoluteString, "https://project.supabase.test/auth/v1/signup")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.body) as? [String: String], [:])
    }

    func testRefreshSendsToken() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, tokenJSON(access: "access-2", refresh: "refresh-2")) }
        let client = SupabaseAuthClient(config: testConfig, session: OnlineStubProtocol.session())
        let session = try await client.refresh("refresh-1")
        XCTAssertEqual(session.refreshToken, "refresh-2")
        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://project.supabase.test/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.body) as? [String: String], ["refresh_token": "refresh-1"])
    }

    func testRejectedRefreshTokenMeansExpiredIdentity() async {
        for status in [400, 401] {
            OnlineStubProtocol.handler = { _, _ in (status, Data(#"{"code":400,"msg":"Invalid Refresh Token"}"#.utf8)) }
            let client = SupabaseAuthClient(config: testConfig, session: OnlineStubProtocol.session())
            do {
                _ = try await client.refresh("old")
                XCTFail("expected identityExpired")
            } catch {
                XCTAssertEqual(error as? OnlineError, .identityExpired)
            }
        }
    }

    func testServerErrorOnSignInIsNotExpiry() async {
        OnlineStubProtocol.handler = { _, _ in (429, Data(#"{"msg":"rate limit"}"#.utf8)) }
        let client = SupabaseAuthClient(config: testConfig, session: OnlineStubProtocol.session())
        do {
            _ = try await client.signInAnonymously()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OnlineError, .server(status: 429, message: "rate limit"))
        }
    }
}

// MARK: - Session

/// Counts calls; each call waits a little so concurrent callers overlap.
private actor FakeAuth: OnlineAuthenticating {
    var signIns = 0
    var refreshes: [String] = []
    var refreshFails = false
    let expiresAt: Date

    init(expiresAt: Date) { self.expiresAt = expiresAt }

    func setRefreshFails(_ fails: Bool) { refreshFails = fails }

    func signInAnonymously() async throws -> AuthSession {
        signIns += 1
        let n = signIns
        try await Task.sleep(for: .milliseconds(50))
        return AuthSession(accessToken: "access-\(n)", refreshToken: "refresh-\(n)", expiresAt: expiresAt, userID: UUID(), isAnonymous: true)
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        refreshes.append(refreshToken)
        try await Task.sleep(for: .milliseconds(50))
        if refreshFails { throw OnlineError.identityExpired }
        return AuthSession(accessToken: "refreshed-\(refreshes.count)", refreshToken: "r-\(refreshes.count)",
                           expiresAt: expiresAt.addingTimeInterval(3600), userID: UUID(), isAnonymous: true)
    }
}

private final class MemoryStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?
    private var expired = false

    init(_ session: AuthSession? = nil) { self.session = session }

    func load() -> AuthSession? { lock.withLock { session } }
    func save(_ session: AuthSession?) { lock.withLock { self.session = session } }
    func loadExpired() -> Bool { lock.withLock { expired } }
    func saveExpired(_ expired: Bool) { lock.withLock { self.expired = expired } }
}

final class OnlineSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testNoIdentityUntilNeeded() async throws {
        let auth = FakeAuth(expiresAt: now.addingTimeInterval(3600))
        let store = MemoryStore()
        let session = OnlineSession(auth: auth, store: store, now: { [now] in now })

        let read = try await session.existingAccessToken()
        XCTAssertNil(read)
        let signIns = await auth.signIns
        XCTAssertEqual(signIns, 0)
        XCTAssertNil(store.load())
    }

    func testConcurrentCallersCreateOneGuest() async throws {
        let auth = FakeAuth(expiresAt: now.addingTimeInterval(3600))
        let store = MemoryStore()
        let session = OnlineSession(auth: auth, store: store, now: { [now] in now })

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 { group.addTask { try await session.accessToken() } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        XCTAssertEqual(Set(tokens), ["access-1"])
        let signIns = await auth.signIns
        XCTAssertEqual(signIns, 1)
        XCTAssertEqual(store.load()?.accessToken, "access-1")
    }

    func testExpiringTokenIsRefreshedOnce() async throws {
        let stored = AuthSession(accessToken: "old", refreshToken: "refresh-old", expiresAt: now.addingTimeInterval(30),
                                 userID: UUID(), isAnonymous: true)
        let auth = FakeAuth(expiresAt: now)
        let store = MemoryStore(stored)
        let session = OnlineSession(auth: auth, store: store, now: { [now] in now })

        async let a = session.accessToken()
        async let b = session.accessToken()
        async let c = session.existingAccessToken()
        let tokens = try await [a, b, c]
        XCTAssertEqual(Set(tokens.compactMap { $0 }), ["refreshed-1"])
        let refreshes = await auth.refreshes
        XCTAssertEqual(refreshes, ["refresh-old"])
        XCTAssertEqual(store.load()?.refreshToken, "r-1")
    }

    func testValidTokenIsReusedWithoutRequests() async throws {
        let stored = AuthSession(accessToken: "fresh", refreshToken: "r", expiresAt: now.addingTimeInterval(600),
                                 userID: UUID(), isAnonymous: true)
        let auth = FakeAuth(expiresAt: now)
        let session = OnlineSession(auth: auth, store: MemoryStore(stored), now: { [now] in now })
        let token = try await session.accessToken()
        XCTAssertEqual(token, "fresh")
        let calls = await (auth.signIns, auth.refreshes.count)
        XCTAssertEqual(calls.0 + calls.1, 0)
    }

    /// Spec: a lost identity is reported, never silently replaced by a new guest.
    func testExpiredIdentityIsNotReplacedSilently() async throws {
        let stored = AuthSession(accessToken: "old", refreshToken: "dead", expiresAt: now.addingTimeInterval(-10),
                                 userID: UUID(), isAnonymous: true)
        let auth = FakeAuth(expiresAt: now.addingTimeInterval(3600))
        await auth.setRefreshFails(true)
        let store = MemoryStore(stored)
        let session = OnlineSession(auth: auth, store: store, now: { [now] in now })

        for _ in 0..<2 {
            do {
                _ = try await session.accessToken()
                XCTFail("expected identityExpired")
            } catch {
                XCTAssertEqual(error as? OnlineError, .identityExpired)
            }
        }
        XCTAssertNil(store.load())
        XCTAssertTrue(store.loadExpired())
        var signIns = await auth.signIns
        XCTAssertEqual(signIns, 0)

        // Still expired after a relaunch.
        let relaunched = OnlineSession(auth: auth, store: store, now: { [now] in now })
        let expired = await relaunched.isExpired
        XCTAssertTrue(expired)

        // Once the user confirms, the next action starts a new guest.
        await relaunched.acceptExpiry()
        let token = try await relaunched.accessToken()
        XCTAssertEqual(token, "access-1")
        signIns = await auth.signIns
        XCTAssertEqual(signIns, 1)
        XCTAssertFalse(store.loadExpired())
    }

    func testSignOutForgetsIdentity() async throws {
        let auth = FakeAuth(expiresAt: now.addingTimeInterval(3600))
        let store = MemoryStore()
        let session = OnlineSession(auth: auth, store: store, now: { [now] in now })
        _ = try await session.accessToken()
        await session.signOut()
        let user = await session.userID
        XCTAssertNil(user)
        XCTAssertNil(store.load())
        XCTAssertFalse(store.loadExpired())
    }
}

// MARK: - PostgREST

final class PostgrestClientTests: XCTestCase {
    private struct Params: Encodable, Sendable {
        let clientArtworkId: UUID
        let capturedOn: String
    }

    private struct Quota: Decodable, Equatable {
        let monthUsed: Int
        let resetsAt: Date
    }

    override func setUp() {
        OnlineStubProtocol.recorded = []
    }

    private func makeClient(session: AuthSession?) -> PostgrestClient {
        let identity = OnlineSession(auth: FakeAuth(expiresAt: .distantFuture), store: MemoryStore(session))
        return PostgrestClient(config: testConfig, identity: identity, session: OnlineStubProtocol.session())
    }

    private let signedIn = AuthSession(accessToken: "user-token", refreshToken: "r", expiresAt: .distantFuture, userID: UUID(), isAnonymous: true)

    func testRPCSendsSnakeCaseParamsAndUserToken() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, Data(#"{"month_used":3,"resets_at":"2026-12-01T00:00:00+00:00"}"#.utf8)) }
        let id = UUID()
        let quota: Quota = try await makeClient(session: signedIn).rpc("my_quota", Params(clientArtworkId: id, capturedOn: "2026-11-12"))
        XCTAssertEqual(quota.monthUsed, 3)
        XCTAssertEqual(quota.resetsAt, OnlineHTTP.parseDate("2026-12-01T00:00:00Z"))

        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://project.supabase.test/rest/v1/rpc/my_quota")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "apikey"), "anon-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: String])
        XCTAssertEqual(body["client_artwork_id"], id.uuidString)
        XCTAssertEqual(body["captured_on"], "2026-11-12")
    }

    func testReadsWithoutIdentityUseAnonKey() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, Data("[]".utf8)) }
        let rows: [Quota] = try await makeClient(session: nil).select("posts", query: [URLQueryItem(name: "select", value: "id")])
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(OnlineStubProtocol.recorded.first?.request.value(forHTTPHeaderField: "Authorization"), "Bearer anon-key")
    }

    func testRefusalHintsBecomeRefusals() async {
        for refusal in OnlineRefusal.allCases {
            OnlineStubProtocol.handler = { _, _ in
                (400, Data(#"{"code":"P0001","message":"refused","details":null,"hint":"\#(refusal.rawValue)"}"#.utf8))
            }
            do {
                let _: PostgrestClient.Empty = try await makeClient(session: signedIn).rpc("create_post", Params(clientArtworkId: UUID(), capturedOn: ""))
                XCTFail("expected a refusal")
            } catch {
                XCTAssertEqual(error as? OnlineError, .refused(refusal))
            }
        }
    }

    func testRejectedTokenIsRefreshedAndRetriedOnce() async throws {
        var calls = 0
        OnlineStubProtocol.handler = { request, _ in
            calls += 1
            let auth = request.value(forHTTPHeaderField: "Authorization")
            return auth == "Bearer user-token" ? (401, Data(#"{"message":"JWT expired"}"#.utf8)) : (200, Data(#"{"month_used":0,"resets_at":"2026-12-01"}"#.utf8))
        }
        let _: Quota = try await makeClient(session: signedIn).rpc("my_quota", Params(clientArtworkId: UUID(), capturedOn: ""))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(OnlineStubProtocol.recorded.last?.request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-1")
    }
}

// MARK: - Dates

final class OnlineDateTests: XCTestCase {
    func testParsesPostgresFormats() throws {
        let a = try XCTUnwrap(OnlineHTTP.parseDate("2026-11-12T03:04:05.123456+00:00"))
        let b = try XCTUnwrap(OnlineHTTP.parseDate("2026-11-12T03:04:05Z"))
        XCTAssertEqual(a.timeIntervalSince(b), 0.123, accuracy: 0.001)
        XCTAssertNotNil(OnlineHTTP.parseDate("2026-11-12"))
        XCTAssertNil(OnlineHTTP.parseDate("yesterday"))
    }

    func testDayStringUsesLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-11-12 23:30 in Tokyo is still the 12th there, already the 12th 14:30 in UTC.
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 23, minute: 30))!
        XCTAssertEqual(OnlineHTTP.dayString(date, calendar: calendar), "2026-11-12")
    }
}

// MARK: - Publishing helpers

final class LocationBlurTests: XCTestCase {
    func testSnapsToGrid() {
        let c = LocationBlur.snap(CLLocationCoordinate2D(latitude: 35.659_49, longitude: 139.700_55))
        XCTAssertEqual(c.latitude, 35.659)
        XCTAssertEqual(c.longitude, 139.701)
        let south = LocationBlur.snap(CLLocationCoordinate2D(latitude: -33.868_82, longitude: -151.209_29))
        XCTAssertEqual(south.latitude, -33.869)
        XCTAssertEqual(south.longitude, -151.209)
    }

    func testIdempotentAndWithinHalfACell() {
        for _ in 0..<1000 {
            let lat = Double.random(in: -85...85), lng = Double.random(in: -180...180)
            let once = LocationBlur.snap(lat), twice = LocationBlur.snap(once)
            XCTAssertEqual(once, twice)
            XCTAssertLessThanOrEqual(abs(once - lat), LocationBlur.gridDegrees / 2 + 1e-9)
            XCTAssertEqual(LocationBlur.snap(LocationBlur.snap(lng)), LocationBlur.snap(lng))
        }
    }
}

final class PublishImageEncoderTests: XCTestCase {
    /// A wide RGBA image: opaque red rectangle in the middle, transparent around it.
    private func cutout(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private func decode(_ data: Data) throws -> (CGImage, [String: Any]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.heic")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        return (image, props)
    }

    private func transparentFraction(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var transparent = 0
        for i in stride(from: 3, to: w * h * 4, by: 4) where px[i] < 8 { transparent += 1 }
        return Double(transparent) / Double(w * h)
    }

    func testSizesTransparencyAndNoMetadata() throws {
        let output = try PublishImageEncoder.encode(cutout(width: 2000, height: 1000))
        XCTAssertEqual(output.fullWidth, 1024)
        XCTAssertEqual(output.fullHeight, 512)

        let (full, fullProps) = try decode(output.full)
        let (thumb, thumbProps) = try decode(output.thumb)
        XCTAssertEqual(max(full.width, full.height), 1024)
        XCTAssertEqual(max(thumb.width, thumb.height), 400)

        // Three quarters of the area is transparent in the source; the encoded images keep it.
        XCTAssertEqual(transparentFraction(full), 0.75, accuracy: 0.05)
        XCTAssertEqual(transparentFraction(thumb), 0.75, accuracy: 0.05)

        for props in [fullProps, thumbProps] {
            XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
            XCTAssertNil(props[kCGImagePropertyExifDictionary as String])
            // HEIC always carries a TIFF block describing its own layout; nothing about the device or time.
            let tiff = (props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
            XCTAssertTrue(Set(tiff.keys).isSubset(of: ["Orientation", "TileWidth", "TileLength"]), "\(tiff.keys)")
            XCTAssertNil(props[kCGImagePropertyIPTCDictionary as String])
            XCTAssertNil(props[kCGImagePropertyMakerAppleDictionary as String])
        }
        XCTAssertLessThan(output.full.count, PublishImageEncoder.fullMaxBytes)
        XCTAssertLessThan(output.thumb.count, PublishImageEncoder.thumbMaxBytes)
    }

    func testSmallCutoutIsNotUpscaled() throws {
        let output = try PublishImageEncoder.encode(cutout(width: 300, height: 200))
        XCTAssertEqual(output.fullWidth, 300)
        let (thumb, _) = try decode(output.thumb)
        XCTAssertEqual(thumb.width, 300)
    }
}

// MARK: - Model

final class ArtworkPublishStateTests: XCTestCase {
    func testStateKeepsVisibilityInStep() {
        let artwork = Artwork()
        XCTAssertEqual(artwork.publishState, .unpublished)
        XCTAssertEqual(artwork.visibility, .privateOnly)

        artwork.remotePostID = UUID()
        artwork.publishState = .pending
        XCTAssertEqual(artwork.visibility, .publicShared)
        artwork.publishedAt = Date()
        artwork.publishState = .published
        XCTAssertEqual(artwork.visibility, .publicShared)

        artwork.publishState = .unpublished
        XCTAssertEqual(artwork.visibility, .privateOnly)
        XCTAssertNil(artwork.remotePostID)
        XCTAssertNil(artwork.publishedAt)
    }
}

// MARK: - Reporting and blocking

final class ReportDraftTests: XCTestCase {
    func testReasonIsRequiredAndOtherNeedsANote() {
        var draft = ReportDraft()
        XCTAssertFalse(draft.canSubmit, "no reason chosen")
        draft.reason = .spam
        XCTAssertTrue(draft.canSubmit, "a basic reason needs no note")
        draft.reason = .other
        draft.note = "   \n"
        XCTAssertFalse(draft.canSubmit, "other needs a note; whitespace is not one")
        draft.note = "  copies someone's art  "
        XCTAssertTrue(draft.canSubmit)
        XCTAssertEqual(draft.trimmedNote, "copies someone's art")
        draft.note = String(repeating: "あ", count: ReportDraft.noteLimit + 1)
        XCTAssertFalse(draft.canSubmit, "note longer than 500 characters")
    }

    func testReasonsFitTheServerColumn() {
        XCTAssertEqual(ReportReason.allCases.last, .other)
        for reason in ReportReason.allCases { XCTAssertTrue((1...32).contains(reason.rawValue.count)) }
    }
}

final class SafetyClientTests: XCTestCase {
    private let user = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

    override func setUp() {
        OnlineStubProtocol.recorded = []
    }

    private func makeClient(signedIn: Bool = true) -> SafetyClient {
        let session = signedIn ? AuthSession(accessToken: "user-token", refreshToken: "r", expiresAt: .distantFuture, userID: user, isAnonymous: true) : nil
        let identity = OnlineSession(auth: FakeAuth(expiresAt: .distantFuture), store: MemoryStore(session))
        let database = PostgrestClient(config: testConfig, identity: identity, session: OnlineStubProtocol.session())
        return SafetyClient(services: OnlineServices(config: testConfig, identity: identity, database: database))
    }

    func testReportSendsReasonAndNote() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, Data(#"{"ok":true}"#.utf8)) }
        let post = UUID()
        try await makeClient().report(postID: post, reason: .other, note: "copies someone's art")
        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://project.supabase.test/rest/v1/rpc/report_post")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: String])
        XCTAssertEqual(body, ["post_id": post.uuidString, "reason": "other", "note": "copies someone's art"])
    }

    func testDailyReportLimitIsARefusal() async {
        OnlineStubProtocol.handler = { _, _ in (400, Data(#"{"code":"P0001","message":"limit","hint":"reports_day"}"#.utf8)) }
        do {
            try await makeClient().report(postID: UUID(), reason: .spam, note: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? OnlineError, .refused(.reportsDay))
            XCTAssertEqual(OnlineMessage.text(for: .refused(.reportsDay)), String(localized: "You've reached today's limit. Please try again later."))
        }
    }

    func testBlockInsertsOwnRowIgnoringDuplicates() async throws {
        OnlineStubProtocol.handler = { _, _ in (201, Data()) }
        try await makeClient().block(userID: other)
        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/rest/v1/blocks")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Prefer"), "return=minimal,resolution=ignore-duplicates")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: String])
        XCTAssertEqual(body, ["blocked_id": other.uuidString], "blocker is the signed-in user, set by the server")
    }

    func testUnblockDeletesThatRow() async throws {
        OnlineStubProtocol.handler = { _, _ in (204, Data()) }
        try await makeClient().unblock(userID: other)
        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.httpMethod, "DELETE")
        XCTAssertEqual(sent.request.url?.query, "blocked_id=eq.\(other.uuidString.lowercased())")
    }

    func testBlockedUsersNewestFirstWithNicknames() async throws {
        let third = UUID()
        OnlineStubProtocol.handler = { request, _ in
            if request.url?.path == "/rest/v1/blocks" {
                return (200, Data("""
                [{"blocked_id":"\(self.other.uuidString.lowercased())","created_at":"2026-11-12T03:00:00+00:00"},
                 {"blocked_id":"\(third.uuidString.lowercased())","created_at":"2026-11-11T03:00:00+00:00"}]
                """.utf8))
            }
            // The second user has no profile any more.
            return (200, Data(#"[{"id":"\#(self.other.uuidString.lowercased())","nickname":"kobayashi"}]"#.utf8))
        }
        let users = try await makeClient().blockedUsers()
        XCTAssertEqual(users.map(\.id), [other, third])
        XCTAssertEqual(users.map(\.nickname), ["kobayashi", nil])
        XCTAssertEqual(OnlineStubProtocol.recorded.first?.request.url?.query?.contains("order=created_at.desc"), true)
    }

    func testBlockedUsersWithoutIdentityCreatesNone() async throws {
        let users = try await makeClient(signedIn: false).blockedUsers()
        XCTAssertTrue(users.isEmpty)
        XCTAssertTrue(OnlineStubProtocol.recorded.isEmpty, "opening the list must not create a guest")
    }
}

@MainActor
final class ExploreBlockingTests: XCTestCase {
    func testBlockedAuthorLeavesTheMapAndTheAreaIsFetchedAgain() async throws {
        let blocked = UUID(), kept = UUID()
        func post(_ author: UUID) -> ExplorePost {
            ExplorePost(id: UUID(), authorId: author, authorNickname: nil, kind: "sticker", lat: 35.66, lng: 139.7, locality: nil,
                        countryCode: nil, capturedOn: nil, width: 1, height: 1, imageKey: nil, thumbKey: nil, likeCount: 0,
                        publishedAt: nil, cellCount: 1)
        }
        let rows = [post(blocked), post(kept)]
        let calls = LockedCounter()
        let model = ExploreModel(fetch: { _, _ in calls.increment(); return rows }, debounce: .zero)
        model.regionChanged(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.66, longitude: 139.7),
                                               span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        for _ in 0..<100 where model.posts.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.posts.count, 2)

        model.authorBlocked(blocked)
        XCTAssertEqual(model.posts.map(\.authorId), [kept], "gone at once, before the refetch")
        for _ in 0..<100 where calls.value < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(calls.value, 2, "the cached area is fetched again")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func increment() { lock.withLock { n += 1 } }
}
