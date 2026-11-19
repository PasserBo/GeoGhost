import Foundation

/// Reads and RPCs against the Supabase database over plain HTTPS (design.md §5).
struct PostgrestClient: Sendable {
    let config: OnlineConfig
    let identity: OnlineSession
    var session: URLSession = .shared

    /// How a call authenticates.
    enum Identity: Sendable {
        /// Needs the user's identity; creates a guest on first use.
        case required
        /// Works without one, but sends it when the user already has one (so blocks apply).
        case ifPresent
    }

    func rpc<Result: Decodable>(_ function: String, _ params: some Encodable & Sendable, identity: Identity = .required,
                                as type: Result.Type = Result.self) async throws -> Result {
        let body = try OnlineHTTP.encoder.encode(params)
        return try await send(path: "rest/v1/rpc/\(function)", query: [], method: "POST", body: body, identity: identity)
    }

    func select<Result: Decodable>(_ table: String, query: [URLQueryItem], identity: Identity = .ifPresent,
                                   as type: Result.Type = Result.self) async throws -> Result {
        try await send(path: "rest/v1/\(table)", query: query, method: "GET", body: nil, identity: identity)
    }

    /// Insert one row; `upsert` ignores a row that already exists.
    func insert(_ table: String, _ row: some Encodable & Sendable, ignoreDuplicates: Bool = true) async throws {
        let body = try OnlineHTTP.encoder.encode(row)
        let prefer = ignoreDuplicates ? "return=minimal,resolution=ignore-duplicates" : "return=minimal"
        let _: Empty = try await send(path: "rest/v1/\(table)", query: [], method: "POST", body: body,
                                      identity: .required, prefer: prefer)
    }

    func delete(_ table: String, matching query: [URLQueryItem]) async throws {
        let _: Empty = try await send(path: "rest/v1/\(table)", query: query, method: "DELETE", body: nil,
                                      identity: .required, prefer: "return=minimal")
    }

    /// For calls whose response body is ignored.
    struct Empty: Decodable, Sendable {}

    private struct ErrorBody: Decodable {
        let code: String?
        let message: String?
        let hint: String?
    }

    private func send<Result: Decodable>(path: String, query: [URLQueryItem], method: String, body: Data?,
                                         identity: Identity, prefer: String? = nil) async throws -> Result {
        let token: String? = switch identity {
        case .required: try await self.identity.accessToken()
        case .ifPresent: try await self.identity.existingAccessToken()
        }
        var (data, response) = try await perform(path: path, query: query, method: method, body: body, token: token, prefer: prefer)
        if response.statusCode == 401, token != nil {
            let retried = try await self.identity.refreshAfterRejection()
            (data, response) = try await perform(path: path, query: query, method: method, body: body, token: retried, prefer: prefer)
        }
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, data: data) }
        if Result.self == Empty.self { return Empty() as! Result }
        do {
            return try OnlineHTTP.decoder.decode(Result.self, from: data)
        } catch {
            throw OnlineError.invalidResponse
        }
    }

    private func perform(path: String, query: [URLQueryItem], method: String, body: Data?, token: String?,
                         prefer: String?) async throws -> (Data, HTTPURLResponse) {
        var url = config.supabaseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return try await OnlineHTTP.send(request, session: session)
    }

    /// PostgREST errors carry the refusal reason in `hint` (design.md §6).
    static func error(status: Int, data: Data) -> OnlineError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        if let hint = body?.hint, let refusal = OnlineRefusal(rawValue: hint) { return .refused(refusal) }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        default: return .server(status: status, message: body?.message)
        }
    }
}
