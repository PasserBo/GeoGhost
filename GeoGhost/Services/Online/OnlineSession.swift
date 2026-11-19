import Foundation

/// Where the session is kept between launches.
protocol SessionStoring: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
    /// Set when the identity stopped being valid, so the next launch still tells the user.
    func loadExpired() -> Bool
    func saveExpired(_ expired: Bool)
}

/// Keeps the session in the Keychain: it survives reinstalling the app on the same phone and never
/// leaves the device (docs/09-online-identity.md §7).
struct KeychainSessionStore: SessionStoring {
    var keychain = KeychainStore(service: "com.passerbo.geoghost.online")

    func load() -> AuthSession? {
        guard let data = try? keychain.data(for: "session") else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            try? keychain.set(data, for: "session")
        } else {
            try? keychain.remove("session")
        }
    }

    func loadExpired() -> Bool { (try? keychain.data(for: "expired")) != nil }

    func saveExpired(_ expired: Bool) {
        if expired { try? keychain.set(Data([1]), for: "expired") } else { try? keychain.remove("expired") }
    }
}

/// The user's online identity. Nothing is created until an action needs it (design.md §3):
/// browsing works without a session; liking, saving, reporting, blocking and publishing create a
/// guest on first use. Refreshes are single-flight because a refresh token can be used only once.
actor OnlineSession {
    private let auth: any OnlineAuthenticating
    private let store: any SessionStoring
    private let now: @Sendable () -> Date
    /// Refresh this long before the access token expires.
    private let leeway: TimeInterval = 60

    private var current: AuthSession?
    private var expired: Bool
    private var pending: Task<AuthSession, any Error>?

    init(auth: any OnlineAuthenticating, store: any SessionStoring = KeychainSessionStore(), now: @escaping @Sendable () -> Date = Date.init) {
        self.auth = auth
        self.store = store
        self.now = now
        self.current = store.load()
        self.expired = store.loadExpired()
    }

    /// The signed-in user, if there is one.
    var userID: UUID? { current?.userID }
    /// The previous identity stopped working and the user has not yet confirmed starting over.
    var isExpired: Bool { expired }

    /// A valid access token, creating a guest if there is no identity yet.
    func accessToken() async throws -> String {
        if expired { throw OnlineError.identityExpired }
        return try await validSession(createIfMissing: true).accessToken
    }

    /// A valid access token if the user already has an identity; nil otherwise. For reads, which
    /// work without an identity but respect the user's blocks when there is one.
    func existingAccessToken() async throws -> String? {
        guard current != nil, !expired else { return nil }
        return try await validSession(createIfMissing: false).accessToken
    }

    /// The server rejected a token that looked valid here (clock skew, revoked): refresh once.
    func refreshAfterRejection() async throws -> String {
        guard let session = current else { throw OnlineError.unauthorized }
        return try await refresh(session).accessToken
    }

    /// After the user confirmed that the expired identity is gone: the next action creates a new guest.
    func acceptExpiry() {
        expired = false
        store.saveExpired(false)
    }

    /// After the user deleted their online data: forget the identity without marking it expired.
    func signOut() {
        pending?.cancel()
        pending = nil
        current = nil
        store.save(nil)
    }

    private func validSession(createIfMissing: Bool) async throws -> AuthSession {
        if let pending { return try await pending.value }
        if let session = current {
            return session.expiresAt.timeIntervalSince(now()) > leeway ? session : try await refresh(session)
        }
        guard createIfMissing else { throw OnlineError.unauthorized }
        return try await run { [auth] in try await auth.signInAnonymously() }
    }

    private func refresh(_ session: AuthSession) async throws -> AuthSession {
        if let pending { return try await pending.value }
        return try await run { [auth] in try await auth.refresh(session.refreshToken) }
    }

    /// Runs one auth request at a time; callers that arrive meanwhile wait for the same result.
    private func run(_ operation: @escaping @Sendable () async throws -> AuthSession) async throws -> AuthSession {
        let task = Task { try await operation() }
        pending = task
        defer { pending = nil }
        do {
            let session = try await task.value
            current = session
            store.save(session)
            return session
        } catch OnlineError.identityExpired {
            current = nil
            expired = true
            store.save(nil)
            store.saveExpired(true)
            throw OnlineError.identityExpired
        }
    }
}
