import XCTest
@testable import GeoGhost

/// spec: online-availability (version gate, pauses, notice, cached settings).
final class AppVersionTests: XCTestCase {
    func testComparesNumerically() {
        XCTAssertLessThan(AppVersion("1.0.9"), AppVersion("1.1.0"))
        XCTAssertLessThan(AppVersion("1.9.0"), AppVersion("1.10.0"))
        XCTAssertEqual(AppVersion("1.1"), AppVersion("1.1.0"))
        XCTAssertFalse(AppVersion("2.0.0") < AppVersion("1.99.99"))
        XCTAssertLessThan(AppVersion("garbage"), AppVersion("0.0.1"))
        XCTAssertEqual(AppVersion(" 1.2.3 ").description, "1.2.3")
    }

    func testThisBuildHasAVersion() {
        XCTAssertGreaterThan(AppVersion.current, AppVersion("1.0.9"))
    }
}

private final class FetchStub: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<RemoteAppConfig, Error>
    private(set) var calls = 0
    init(_ result: Result<RemoteAppConfig, Error>) { self.result = result }
    func set(_ result: Result<RemoteAppConfig, Error>) { lock.withLock { self.result = result } }
    func callAsFunction() throws -> RemoteAppConfig {
        try lock.withLock { calls += 1; return try result.get() }
    }
}

@MainActor
final class AppConfigServiceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AppConfigServiceTests")!
        defaults.removePersistentDomain(forName: "AppConfigServiceTests")
    }

    private func config(min: String = "1.1.0", latest: String = "1.1.0", publishing: Bool = true, signups: Bool = true,
                        notice: [String: String]? = nil) -> RemoteAppConfig {
        RemoteAppConfig(minOnlineVersion: min, latestVersion: latest, publishingEnabled: publishing, signupsEnabled: signups, notice: notice)
    }

    private func service(_ stub: FetchStub, version: String = "1.1.0") -> AppConfigService {
        AppConfigService(fetch: { try stub() }, defaults: defaults, appVersion: AppVersion(version))
    }

    func testNeverReadMeansEverythingAllowed() async {
        let stub = FetchStub(.failure(OnlineError.offline))
        let s = service(stub)
        await s.refresh()
        XCTAssertEqual(s.availability, .ok)
        XCTAssertFalse(s.publishingPaused)
        XCTAssertFalse(s.signupsPaused)
        XCTAssertNil(s.notice(language: "en"))
    }

    func testAvailabilityFollowsVersions() async {
        let stub = FetchStub(.success(config(min: "1.1.0", latest: "1.2.0")))
        let s = service(stub, version: "1.1.0")
        await s.refresh()
        XCTAssertEqual(s.availability, .updateAvailable)

        stub.set(.success(config(min: "1.2.0", latest: "1.2.0")))
        await s.refresh()
        XCTAssertEqual(s.availability, .updateRequired)
        XCTAssertTrue(s.updateRequired)

        stub.set(.success(config(min: "1.0.0", latest: "1.1.0")))
        await s.refresh()
        XCTAssertEqual(s.availability, .ok)
    }

    func testPausesAreReported() async {
        let stub = FetchStub(.success(config(publishing: false, signups: false)))
        let s = service(stub)
        await s.refresh()
        XCTAssertTrue(s.publishingPaused)
        XCTAssertTrue(s.signupsPaused)
        XCTAssertEqual(s.availability, .ok)
    }

    func testReadsAgainEveryTime() async {
        // Every return to the foreground reads again, so a new notice shows up right away.
        let stub = FetchStub(.success(config()))
        let s = service(stub)
        await s.refresh()
        XCTAssertNil(s.notice(language: "en"))
        stub.set(.success(config(notice: ["en": "Maintenance tonight"])))
        await s.refresh()
        XCTAssertEqual(stub.calls, 2)
        XCTAssertEqual(s.notice(language: "en"), "Maintenance tonight")
    }

    func testFailureKeepsLastSettingsAcrossLaunches() async {
        let stub = FetchStub(.success(config(publishing: false)))
        await service(stub).refresh()

        // Next launch, offline: the saved settings still apply.
        stub.set(.failure(OnlineError.offline))
        let relaunched = service(stub)
        XCTAssertTrue(relaunched.publishingPaused)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.publishingPaused)
    }

    func testNoticeUsesTheAppLanguageElseEnglish() async {
        let stub = FetchStub(.success(config(notice: ["en": "Maintenance tonight", "ja": "今夜メンテナンス"])))
        let s = service(stub)
        await s.refresh()
        XCTAssertEqual(s.notice(language: "ja"), "今夜メンテナンス")
        XCTAssertEqual(s.notice(language: "zh-Hans"), "Maintenance tonight")
        XCTAssertEqual(s.notice(language: "en"), "Maintenance tonight")
    }

    func testDecodesTheServerRow() throws {
        let json = #"[{"min_online_version":"1.1.0","latest_version":"1.2.0","publishing_enabled":false,"signups_enabled":true,"notice":{"en":"Hi","zh-Hans":"你好"}}]"#
        let rows = try OnlineHTTP.decoder.decode([RemoteAppConfig].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first, config(min: "1.1.0", latest: "1.2.0", publishing: false, notice: ["en": "Hi", "zh-Hans": "你好"]))
    }
}

final class VersionHeaderTests: XCTestCase {
    private let testConfig = OnlineConfig(supabaseURL: URL(string: "https://project.supabase.test")!, anonKey: "anon-key",
                                          apiURL: URL(string: "https://api.test")!, imageBaseURL: URL(string: "https://api.test/v1/images")!)

    override func setUp() {
        OnlineStubProtocol.recorded = []
    }

    func testEveryRequestCarriesTheAppVersion() async throws {
        OnlineStubProtocol.handler = { _, _ in (200, Data("[]".utf8)) }
        let identity = OnlineSession(auth: SupabaseAuthClient(config: testConfig, session: OnlineStubProtocol.session()))
        let database = PostgrestClient(config: testConfig, identity: identity, session: OnlineStubProtocol.session())
        let _: [RemoteAppConfig] = try await database.select("app_config", query: [])
        let sent = try XCTUnwrap(OnlineStubProtocol.recorded.first)
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "X-GeoGhost-Version"), AppVersion.currentString)
    }

    func testServerRefusalsMapToTheirOwnReasons() {
        for (status, hint, refusal) in [(400, "update_required", OnlineRefusal.updateRequired),
                                        (400, "publishing_paused", .publishingPaused),
                                        (400, "signups_paused", .signupsPaused)] {
            let body = Data(#"{"code":"P0001","message":"x","hint":"\#(hint)"}"#.utf8)
            XCTAssertEqual(PostgrestClient.error(status: status, data: body), .refused(refusal))
        }
        // The Worker answers 426 for an outdated app.
        let worker = OnlineHTTP.workerError(status: 426, data: Data(#"{"error":"update_required","message":"x"}"#.utf8))
        XCTAssertEqual(worker, .refused(.updateRequired))
    }

    func testAPauseIsNeverWordedAsAUsedUpQuota() {
        let quota = OnlineMessage.text(for: OnlineError.refused(.quotaMonth))
        for refusal in [OnlineRefusal.updateRequired, .publishingPaused, .signupsPaused] {
            let text = OnlineMessage.text(for: OnlineError.refused(refusal))
            XCTAssertNotEqual(text, quota)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("limit"), text)
        }
    }
}
