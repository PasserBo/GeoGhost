import Foundation

/// What the server needs to create a public post (design.md §5 `create_post`). Coordinates are
/// already snapped; nothing here identifies the device, the exact place or the time of day.
struct PostDraft: Encodable, Sendable, Equatable {
    let clientArtworkId: UUID
    let kind: String
    let lat: Double
    let lng: Double
    let locality: String?
    let countryCode: String?
    let capturedOn: String
    let width: Int
    let height: Int
}

struct CreatedPost: Decodable, Sendable, Equatable {
    let postId: UUID
    let status: String
}

/// This month's and today's publishing (design.md §5 `my_quota`).
struct PublishQuota: Decodable, Sendable, Equatable {
    let monthUsed: Int
    let monthLimit: Int
    let dayUsed: Int
    let dayLimit: Int
    let resetsAt: Date

    var monthRemaining: Int { max(0, monthLimit - monthUsed) }
    var dayRemaining: Int { max(0, dayLimit - dayUsed) }
}

/// Server side of publishing, so the flow can be tested without a backend.
protocol PublishBackend: Sendable {
    func quota() async throws -> PublishQuota
    func createPost(_ draft: PostDraft) async throws -> CreatedPost
    /// Returns the post's status once its images are stored.
    func uploadImages(postID: UUID, images: PublishImageEncoder.Output) async throws -> String
    func retract(postID: UUID) async throws
    /// Current status of each post the user still has on the server; missing ids are gone.
    /// A post back in review after reports is `PublishState.reReviewStatus`.
    func statuses(of postIDs: [UUID]) async throws -> [UUID: String]
}

/// Publishing over the database RPCs and the Worker (design.md §5, §7, §8).
struct PublishClient: PublishBackend {
    let services: OnlineServices
    var session: URLSession = .shared

    func quota() async throws -> PublishQuota {
        try await services.database.rpc("my_quota", NoParams())
    }

    func createPost(_ draft: PostDraft) async throws -> CreatedPost {
        try await services.database.rpc("create_post", draft)
    }

    func uploadImages(postID: UUID, images: PublishImageEncoder.Output) async throws -> String {
        let boundary = "geoghost-\(UUID().uuidString)"
        var body = Data()
        for (name, data) in [("full", images.full), ("thumb", images.thumb)] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(name).heic\"\r\nContent-Type: image/heic\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        let data = try await services.worker("PUT", path: "v1/posts/\(postID.uuidString.lowercased())/images", body: body,
                                             contentType: "multipart/form-data; boundary=\(boundary)", session: session)
        struct Response: Decodable { let status: String }
        guard let response = try? OnlineHTTP.decoder.decode(Response.self, from: data) else { throw OnlineError.invalidResponse }
        return response.status
    }

    func retract(postID: UUID) async throws {
        do {
            _ = try await services.worker("DELETE", path: "v1/posts/\(postID.uuidString.lowercased())", body: nil, contentType: nil, session: session)
        } catch OnlineError.notFound {
            // Already gone on the server: the retraction has happened.
        }
    }

    func statuses(of postIDs: [UUID]) async throws -> [UUID: String] {
        guard !postIDs.isEmpty else { return [:] }
        struct Row: Decodable { let id: UUID; let status: String; let publishedAt: Date? }
        let ids = postIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let rows: [Row] = try await services.database.select("posts", query: [
            URLQueryItem(name: "select", value: "id,status,published_at"), URLQueryItem(name: "id", value: "in.(\(ids))"),
        ], identity: .required)
        // In review but published before: back in review after reports (migration 20261112030000).
        return Dictionary(rows.map { ($0.id, $0.status == "pending" && $0.publishedAt != nil ? PublishState.reReviewStatus : $0.status) },
                          uniquingKeysWith: { a, _ in a })
    }

    private struct NoParams: Encodable, Sendable {}
}

extension PublishState {
    /// Not a database value: `pending` with `published_at` set, as `statuses(of:)` reports it.
    static let reReviewStatus = "pending_re_review"

    /// The local state for a server status (design.md §4). Removed posts are private again.
    init(serverStatus: String?) {
        switch serverStatus {
        case "uploading": self = .uploading
        case "pending": self = .pending
        case Self.reReviewStatus: self = .reReview
        case "public": self = .published
        case "hidden": self = .rejected
        default: self = .unpublished
        }
    }
}
