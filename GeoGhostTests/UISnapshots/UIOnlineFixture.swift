import Foundation
import UIKit
@testable import GeoGhost

/// An online backend that never leaves the process. The app's own clients run unchanged; their
/// requests are answered here from fixed data, so screens that load from the server show the
/// same thing on every run and nothing depends on the network.
///
/// What the server "holds" is the `scenario`; a catalog entry sets it before building its screen.
@MainActor
enum UIOnlineFixture {
    struct Scenario: Sendable {
        /// Posts used today and this month, out of 5 and 20.
        var dayUsed = 1
        var monthUsed = 4
        var blockedUsers = 0
        /// The user has chosen a nickname and agreed to the rules.
        var hasProfile = true
    }

    static var scenario: Scenario {
        get { FixtureServer.scenario }
        set { FixtureServer.scenario = newValue }
    }

    static let config = OnlineConfig(supabaseURL: URL(string: "https://db.fixture.invalid")!, anonKey: "fixture",
                                     apiURL: URL(string: "https://api.fixture.invalid")!,
                                     imageBaseURL: URL(string: "https://images.fixture.invalid")!)

    static let userID = UIFixtures.id(post: 7)

    /// A guest who is already signed in, so no screen has to create an identity.
    private struct SignedInStore: SessionStoring {
        let session: AuthSession
        func load() -> AuthSession? { session }
        func save(_ session: AuthSession?) {}
        func loadExpired() -> Bool { false }
        func saveExpired(_ expired: Bool) {}
    }

    private struct NoAuth: OnlineAuthenticating {
        func signInAnonymously() async throws -> AuthSession { throw OnlineError.offline }
        func refresh(_ refreshToken: String) async throws -> AuthSession { throw OnlineError.offline }
    }

    static func makeState() -> OnlineState {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FixtureServer.self]
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: .distantFuture, userID: userID, isAnonymous: true)
        let identity = OnlineSession(auth: NoAuth(), store: SignedInStore(session: session))
        let database = PostgrestClient(config: config, identity: identity, session: URLSession(configuration: sessionConfiguration))
        return OnlineState(services: OnlineServices(config: config, identity: identity, database: database))
    }

    /// Someone else's public piece, as the world map returns it.
    static let post = ExplorePost(id: UIFixtures.id(post: 1), authorId: UIFixtures.id(post: 99), authorNickname: "sticker_hunter",
                                  kind: "sticker", lat: 35.70, lng: 139.65, locality: "杉並区", countryCode: "JP",
                                  capturedOn: "2026-06-21", width: 600, height: 600, imageKey: "cat.png", thumbKey: "cat.png",
                                  likeCount: 12, publishedAt: nil, cellCount: 1)

    /// Images are fetched through `URLSession.shared`, so the server has to be registered for it too.
    static func install() { URLProtocol.registerClass(FixtureServer.self) }
    static func uninstall() { URLProtocol.unregisterClass(FixtureServer.self) }
}

/// Answers the requests the app makes to `*.fixture.invalid`. Anything it has no answer for fails
/// as "not connected", which the app shows as being offline.
final class FixtureServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var scenario = UIOnlineFixture.Scenario()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasSuffix("fixture.invalid") ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let (body, type) = Self.answer(url: url, body: Self.body(of: request)) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands a request's body over as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private static func answer(url: URL, body: Data) -> (Data, String)? {
        let scenario = Self.scenario
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func json(_ value: Any) -> (Data, String)? {
            (try? JSONSerialization.data(withJSONObject: value)).map { ($0, "application/json") }
        }

        if url.host() == "images.fixture.invalid" {
            let pictures: [String: (FixturePicture.Shape, String)] = [
                "cat.png": (.cat, "#FF6B2C"), "ghost.png": (.ghost, "#3A8DF2"), "star.png": (.star, "#8C5CF5"),
                "hexagon.png": (.hexagon, "#E8457A"),
            ]
            guard let (shape, hex) = pictures[url.lastPathComponent] else { return nil }
            return (FixturePicture.pngData(shape, hex: hex), "image/png")
        }

        switch url.path() {
        case "/rest/v1/rpc/my_quota":
            return json(["month_used": scenario.monthUsed, "month_limit": 20, "day_used": scenario.dayUsed, "day_limit": 5,
                         "resets_at": "2026-09-01T00:00:00Z"])

        case "/rest/v1/blocks":
            let names = ["2026-08-20T09:00:00Z", "2026-07-02T18:30:00Z", "2026-05-14T12:00:00Z"]
            return json((0..<min(scenario.blockedUsers, names.count)).map { i in
                ["blocked_id": blockedID(i), "created_at": names[i]]
            })

        case "/rest/v1/profiles":
            // The list of blocked users asks for several ids; one's own profile asks for one.
            if query.contains(where: { $0.name == "id" && ($0.value ?? "").hasPrefix("in.") }) {
                // The third one has since deleted their profile.
                let nicknames = ["spray_can_sam", "tagger_2000"]
                return json(nicknames.enumerated().map { i, name in ["id": blockedID(i), "nickname": name] })
            }
            guard scenario.hasProfile else { return json([[String: Any]]()) }
            return json([["id": UIOnlineFixture.fixtureUserID, "nickname": "ghost_collector", "terms_version": 1,
                          "nickname_changed_at": "2026-01-10T00:00:00Z"]])

        case "/rest/v1/rpc/explore":
            // The same pieces whatever area is asked for: the map opens by framing what it is given,
            // so it always opens on these.
            let places: [(Double, Double, String, String, Int)] = [
                (35.7023, 139.6497, "sticker", "cat.png", 1), (35.6614, 139.6680, "tag", "ghost.png", 1),
                (35.7148, 139.7745, "graffiti", "star.png", 1), (35.6190, 139.7280, "sticker", "hexagon.png", 14),
            ]
            return json(places.enumerated().map { i, place in
                ["id": String(format: "c0000000-0000-4000-8000-%012d", i + 1), "author_id": "c0000000-0000-4000-8000-000000000099",
                 "author_nickname": "sticker_hunter", "kind": place.2, "lat": place.0, "lng": place.1,
                 "locality": "杉並区", "country_code": "JP", "captured_on": "2026-06-21", "width": 600, "height": 600,
                 "image_key": place.3, "thumb_key": place.3, "like_count": 3 + i, "cell_count": place.4] as [String: Any]
            })

        default:
            return nil
        }
    }

    private static func blockedID(_ index: Int) -> String { String(format: "d0000000-0000-4000-8000-%012d", index + 1) }
}

extension UIOnlineFixture {
    nonisolated static let fixtureUserID = "b0000000-0000-4000-8000-000000000007"
}
