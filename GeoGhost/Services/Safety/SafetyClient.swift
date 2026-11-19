import Foundation

/// Why a post is reported (spec: content-safety › 举报贴纸), in the order the report sheet lists them.
/// The raw value is what the server stores.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case sexualOrViolent = "sexual_violent"
    case hateOrHarassment = "hate_harassment"
    case privacy
    case spam
    case other

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .sexualOrViolent: "Sexual or violent content"
        case .hateOrHarassment: "Hate or harassment"
        case .privacy: "Exposes someone's privacy (faces, plates, addresses)"
        case .spam: "Advertising or spam"
        case .other: "Something else"
        }
    }

    /// "Something else" needs a note so the report can be handled.
    var requiresNote: Bool { self == .other }
}

/// What the report sheet sends, checked before it can be submitted.
struct ReportDraft: Equatable, Sendable {
    static let noteLimit = 500

    var reason: ReportReason?
    var note = ""

    /// The note as sent: trimmed, nil when empty.
    var trimmedNote: String? {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var canSubmit: Bool {
        guard let reason else { return false }
        if let n = trimmedNote, n.count > Self.noteLimit { return false }
        return !reason.requiresNote || trimmedNote != nil
    }
}

/// Someone the user blocked, newest first in the list.
struct BlockedUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let nickname: String?
    let blockedAt: Date
}

/// Server side of reporting and blocking, so the screens can be tested without a backend.
protocol SafetyBackend: Sendable {
    /// Refusals: `.refused(.reportsDay)`. Reporting the same post again succeeds without counting.
    func report(postID: UUID, reason: ReportReason, note: String?) async throws
    func block(userID: UUID) async throws
    func unblock(userID: UUID) async throws
    /// Empty when the user has no online identity yet (listing never creates one).
    func blockedUsers() async throws -> [BlockedUser]
}

/// Reporting and blocking over the database (setup-online-backend design.md §5): `report_post`
/// and the user's own rows in `blocks`. Both create a guest on first use.
struct SafetyClient: SafetyBackend {
    let services: OnlineServices

    func report(postID: UUID, reason: ReportReason, note: String?) async throws {
        struct Params: Encodable, Sendable { let postId: UUID; let reason: String; let note: String? }
        let _: PostgrestClient.Empty = try await services.database.rpc("report_post", Params(postId: postID, reason: reason.rawValue, note: note))
    }

    func block(userID: UUID) async throws {
        struct Row: Encodable, Sendable { let blockedId: UUID }
        try await services.database.insert("blocks", Row(blockedId: userID))
    }

    func unblock(userID: UUID) async throws {
        try await services.database.delete("blocks", matching: [URLQueryItem(name: "blocked_id", value: "eq.\(userID.uuidString.lowercased())")])
    }

    func blockedUsers() async throws -> [BlockedUser] {
        guard await services.identity.userID != nil else { return [] }
        struct Block: Decodable { let blockedId: UUID; let createdAt: Date }
        struct Profile: Decodable { let id: UUID; let nickname: String }
        let blocks: [Block] = try await services.database.select("blocks", query: [
            URLQueryItem(name: "select", value: "blocked_id,created_at"), URLQueryItem(name: "order", value: "created_at.desc"),
        ], identity: .required)
        guard !blocks.isEmpty else { return [] }
        let ids = blocks.map { $0.blockedId.uuidString.lowercased() }.joined(separator: ",")
        let profiles: [Profile] = try await services.database.select("profiles", query: [
            URLQueryItem(name: "select", value: "id,nickname"), URLQueryItem(name: "id", value: "in.(\(ids))"),
        ], identity: .required)
        let names = Dictionary(profiles.map { ($0.id, $0.nickname) }, uniquingKeysWith: { a, _ in a })
        return blocks.map { BlockedUser(id: $0.blockedId, nickname: names[$0.blockedId], blockedAt: $0.createdAt) }
    }
}

extension OnlineServices {
    var safety: SafetyClient { SafetyClient(services: self) }
}

/// Lets other screens react when the user blocks or unblocks someone (the world map drops or
/// refetches that person's posts).
extension Notification.Name {
    static let onlineBlocksChanged = Notification.Name("GeoGhost.onlineBlocksChanged")
    /// Object: the reported post's id. The world map drops it.
    static let onlinePostReported = Notification.Name("GeoGhost.onlinePostReported")
}
