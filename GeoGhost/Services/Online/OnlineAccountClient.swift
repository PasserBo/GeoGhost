import Foundation

/// The user's public profile. Fields other than the nickname are only filled for the user's own row.
struct OnlineProfile: Decodable, Sendable, Equatable {
    let id: UUID
    let nickname: String
    let termsVersion: Int?
    let nicknameChangedAt: Date?
}

/// Nickname, community rules and deleting the user's online data (spec: online-identity).
struct OnlineAccountClient: Sendable {
    let services: OnlineServices
    var session: URLSession = .shared

    /// The user's own profile, or nil if they have not set a nickname yet (or have no identity).
    func ownProfile() async throws -> OnlineProfile? {
        guard let user = await services.identity.userID else { return nil }
        let rows: [OnlineProfile] = try await services.database.select("profiles", query: [
            URLQueryItem(name: "select", value: "id,nickname,terms_version,nickname_changed_at"),
            URLQueryItem(name: "id", value: "eq.\(user.uuidString.lowercased())"),
        ], identity: .required)
        return rows.first
    }

    /// Sets the nickname and records agreement to the given version of the community rules.
    /// Refusals: `.nicknameCooldown`, `.banned`.
    func saveProfile(nickname: String, termsVersion: Int) async throws -> OnlineProfile {
        struct Params: Encodable, Sendable { let nickname: String; let termsVersion: Int }
        return try await services.database.rpc("upsert_profile", Params(nickname: nickname, termsVersion: termsVersion))
    }

    /// Deletes every post, image, like, save, block and the profile on the server, then forgets
    /// the identity on this device; the next online action starts a new guest. Local pieces stay.
    func deleteMyOnlineData() async throws {
        _ = try await services.worker("DELETE", path: "v1/me", body: nil, contentType: nil, session: session)
        await services.identity.signOut()
    }
}
