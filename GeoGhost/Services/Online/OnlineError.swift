import Foundation

/// Why the server refused an action. Raw values are the hints the server sends
/// (docs/spec/changes/setup-online-backend/design.md §6).
enum OnlineRefusal: String, Sendable, CaseIterable {
    case quotaDay = "quota_day"
    case quotaMonth = "quota_month"
    case savesFull = "saves_full"
    case likesDay = "likes_day"
    case reportsDay = "reports_day"
    case banned
    case termsRequired = "terms_required"
    case profileRequired = "profile_required"
    case nicknameCooldown = "nickname_cooldown"
}

enum OnlineError: Error, Equatable {
    /// The build has no backend configured.
    case notConfigured
    /// No connection, or the server could not be reached.
    case offline
    /// The guest identity is no longer valid. The user has to confirm before a new guest is created,
    /// because the old one's posts can no longer be managed.
    case identityExpired
    case refused(OnlineRefusal)
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case tooLarge
    case unsupportedImage
    case server(status: Int, message: String?)
    case invalidResponse
}

/// URLSession calls with errors mapped to `OnlineError`.
enum OnlineHTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw isOffline(error) ? OnlineError.offline : OnlineError.server(status: 0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw OnlineError.invalidResponse }
        return (data, http)
    }

    static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            true
        default:
            false
        }
    }

    /// Maps a non-2xx status from the Worker (`{"error", "message"}`) to an error.
    static func workerError(status: Int, data: Data) -> OnlineError {
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let hint = body?["error"] as? String, let refusal = OnlineRefusal(rawValue: hint) { return .refused(refusal) }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 413: return .tooLarge
        case 415: return .unsupportedImage
        default: return .server(status: status, message: body?["message"] as? String)
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Postgres timestamps (`2026-11-12T03:04:05.123456+00:00`) and plain dates (`2026-11-12`).
    static func parseDate(_ s: String) -> Date? {
        let options: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate],
        ]
        for option in options {
            let f = ISO8601DateFormatter()
            f.formatOptions = option
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// A calendar day as the server stores it (`yyyy-MM-dd`, the user's local day).
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
