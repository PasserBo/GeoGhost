import Foundation

/// A signed-in identity (a guest until it is linked to an Apple account).
struct AuthSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var isAnonymous: Bool
}

protocol OnlineAuthenticating: Sendable {
    func signInAnonymously() async throws -> AuthSession
    /// Throws `OnlineError.identityExpired` when the refresh token is no longer accepted.
    func refresh(_ refreshToken: String) async throws -> AuthSession
}

/// Supabase Auth over plain HTTPS (design.md §3).
struct SupabaseAuthClient: OnlineAuthenticating {
    let config: OnlineConfig
    var session: URLSession = .shared
    var now: @Sendable () -> Date = Date.init

    func signInAnonymously() async throws -> AuthSession {
        try await post(path: "auth/v1/signup", query: nil, body: [:], refreshing: false)
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        try await post(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                       body: ["refresh_token": refreshToken], refreshing: true)
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: UUID
            let isAnonymous: Bool?
        }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User
    }

    private func post(path: String, query: [URLQueryItem]?, body: [String: String], refreshing: Bool) async throws -> AuthSession {
        var url = config.supabaseURL.appending(path: path)
        if let query { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let sentAt = now()
        let (data, response) = try await OnlineHTTP.send(request, session: session)
        switch response.statusCode {
        case 200..<300:
            guard let token = try? OnlineHTTP.decoder.decode(TokenResponse.self, from: data) else { throw OnlineError.invalidResponse }
            return AuthSession(accessToken: token.accessToken, refreshToken: token.refreshToken,
                               expiresAt: sentAt.addingTimeInterval(token.expiresIn), userID: token.user.id,
                               isAnonymous: token.user.isAnonymous ?? true)
        case 400...403 where refreshing:
            // Supabase answers an unknown, revoked or reused refresh token with 400 or 401.
            throw OnlineError.identityExpired
        default:
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (body?["msg"] ?? body?["message"] ?? body?["error_description"]) as? String
            throw OnlineError.server(status: response.statusCode, message: message)
        }
    }
}
