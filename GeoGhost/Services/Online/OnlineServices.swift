import Foundation

/// Everything that talks to the online backend, built once from the configuration.
struct OnlineServices: Sendable {
    let config: OnlineConfig
    let identity: OnlineSession
    let database: PostgrestClient

    init(config: OnlineConfig) {
        let identity = OnlineSession(auth: SupabaseAuthClient(config: config))
        self.init(config: config, identity: identity, database: PostgrestClient(config: config, identity: identity))
    }

    init(config: OnlineConfig, identity: OnlineSession, database: PostgrestClient) {
        self.config = config
        self.identity = identity
        self.database = database
    }

    var publishing: PublishClient { PublishClient(services: self) }
    var account: OnlineAccountClient { OnlineAccountClient(services: self) }
}

extension OnlineServices {
    /// A Worker call as the signed-in user (design.md §7); a rejected token is refreshed and the
    /// call retried once. Errors come back as `OnlineError`.
    func worker(_ method: String, path: String, body: Data?, contentType: String?, session: URLSession = .shared) async throws -> Data {
        var token = try await identity.accessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: config.apiURL.appending(path: path), timeoutInterval: 60)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            request.httpBody = body
            let (data, response) = try await OnlineHTTP.send(request, session: session)
            if (200..<300).contains(response.statusCode) { return data }
            if response.statusCode == 401, attempt == 0 {
                token = try await identity.refreshAfterRejection()
                continue
            }
            throw OnlineHTTP.workerError(status: response.statusCode, data: data)
        }
        throw OnlineError.unauthorized
    }
}
