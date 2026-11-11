import Foundation

/// Where the online backend lives (docs/spec/changes/setup-online-backend/design.md §2).
/// Read from Info.plist, which Config/Online.xcconfig fills in. When any value is missing, online
/// features stay hidden and the app behaves like the offline v1.0.
struct OnlineConfig: Sendable, Equatable {
    let supabaseURL: URL
    /// The anon (publishable) key. Public by design: what it may do is decided by the server's rules.
    let anonKey: String
    /// The Worker that accepts image uploads and deletions.
    let apiURL: URL
    /// Images are read from `<imageBaseURL>/<key>`.
    let imageBaseURL: URL

    static let current = OnlineConfig(info: Bundle.main.infoDictionary ?? [:])

    func imageURL(key: String) -> URL { imageBaseURL.appending(path: key) }
}

extension OnlineConfig {
    init?(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let s = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                  !s.hasPrefix("$(") else { return nil }
            return s
        }
        func url(_ key: String) -> URL? {
            guard let s = value(key), let u = URL(string: s), u.scheme == "https" || u.scheme == "http", u.host() != nil else { return nil }
            return u
        }
        guard let supabase = url("GGSupabaseURL"), let key = value("GGSupabaseAnonKey"),
              let api = url("GGOnlineAPIURL"), let images = url("GGImageBaseURL") else { return nil }
        self.init(supabaseURL: supabase, anonKey: key, apiURL: api, imageBaseURL: images)
    }
}
