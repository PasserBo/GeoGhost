import Foundation
import Observation

/// An app version compared as numbers, `major.minor.patch` (spec: online-availability).
/// Missing or non-numeric parts count as 0 — the same rule as the server's `private.version_lt`
/// and the Worker's `versionLessThan`.
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        func number(_ i: Int) -> Int {
            guard i < parts.count else { return 0 }
            return Int(parts[i].prefix(while: { $0.isASCII && $0.isNumber }).prefix(9)) ?? 0
        }
        (major, minor, patch) = (number(0), number(1), number(2))
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    /// This build's version, as sent in `X-GeoGhost-Version`.
    static let currentString = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    static let current = AppVersion(currentString)
}

/// The operator's settings, read from the server (`app_config`).
struct RemoteAppConfig: Codable, Sendable, Equatable {
    var minOnlineVersion: String
    var latestVersion: String
    var publishingEnabled: Bool
    var signupsEnabled: Bool
    /// Optional notice by language: `en`, `ja`, `zh-Hans`.
    var notice: [String: String]?
}

enum OnlineAvailability: Equatable {
    case ok
    /// A newer version exists; everything keeps working.
    case updateAvailable
    /// This version may no longer use online features. Local collecting is unaffected.
    case updateRequired
}

/// Reads the operator's settings at launch and when the app comes back, at most every 10 minutes.
/// A failed read keeps the last settings; with none ever read, everything is allowed (the server
/// checks again).
@Observable
@MainActor
final class AppConfigService {
    typealias Fetch = @Sendable () async throws -> RemoteAppConfig

    static let maxAge: TimeInterval = 10 * 60
    static let cacheKey = "onlineAppConfig"

    private(set) var config: RemoteAppConfig?
    let appVersion: AppVersion
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    init(fetch: @escaping Fetch, defaults: UserDefaults = .standard, appVersion: AppVersion = .current,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.defaults = defaults
        self.appVersion = appVersion
        self.now = now
        if let data = defaults.data(forKey: Self.cacheKey) {
            config = try? JSONDecoder().decode(RemoteAppConfig.self, from: data)
        }
    }

    convenience init(services: OnlineServices) {
        let database = services.database
        self.init(fetch: {
            let rows: [RemoteAppConfig] = try await database.select("app_config", query: [
                URLQueryItem(name: "select", value: "min_online_version,latest_version,publishing_enabled,signups_enabled,notice"),
            ])
            guard let first = rows.first else { throw OnlineError.invalidResponse }
            return first
        })
    }

    var availability: OnlineAvailability {
        guard let config else { return .ok }
        if appVersion < AppVersion(config.minOnlineVersion) { return .updateRequired }
        if appVersion < AppVersion(config.latestVersion) { return .updateAvailable }
        return .ok
    }

    var updateRequired: Bool { availability == .updateRequired }
    var publishingPaused: Bool { config?.publishingEnabled == false }
    var signupsPaused: Bool { config?.signupsEnabled == false }

    /// The notice in the app's language, else English; nil when there is none.
    func notice(language: String? = Bundle.main.preferredLocalizations.first) -> String? {
        guard let notice = config?.notice else { return nil }
        let key = language.map { $0.hasPrefix("zh") ? "zh-Hans" : String($0.prefix(2)) } ?? "en"
        let text = notice[key] ?? notice["en"]
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func refresh(force: Bool = false) async {
        if !force, let fetchedAt, now().timeIntervalSince(fetchedAt) < Self.maxAge { return }
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let fresh = try await fetch()
            fetchedAt = now()
            if fresh != config { config = fresh }
            if let data = try? JSONEncoder().encode(fresh) { defaults.set(data, forKey: Self.cacheKey) }
        } catch {
            // Keep the last settings; try again next time.
        }
    }

    /// The server refused because of a setting this app hasn't seen yet: read the settings again
    /// so every screen shows the same reason.
    func noteRefusal(_ error: any Error) {
        guard case let .refused(refusal)? = error as? OnlineError,
              [.updateRequired, .publishingPaused, .signupsPaused].contains(refusal) else { return }
        Task { await refresh(force: true) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
