import Foundation
import Observation

/// The newest public pieces in the whole world: what the world map opens on and what its strip of
/// latest finds shows. Fetched in the background when the app starts and kept on disk, so the map
/// usually has something to show the moment it is opened (and still has after a launch offline).
@Observable
@MainActor
final class WorldFeed {
    typealias Fetch = @Sendable () async throws -> [ExplorePost]

    /// The server returns at most this many; fewer means these are all the public pieces there are.
    nonisolated static let limit = 200

    enum Phase: Equatable { case idle, loading, loaded, failed(OnlineError) }

    private(set) var posts: [ExplorePost] = []
    private(set) var phase: Phase = .idle
    /// `posts` came from disk and hasn't been confirmed by the server yet.
    private(set) var isFromDisk = false

    /// Every public piece is in `posts`, so areas and pins can be worked out without asking again.
    var isComplete: Bool { posts.count < Self.limit }
    /// There is something to decide the opening view with, fresh or remembered.
    var hasContent: Bool { phase == .loaded || isFromDisk }

    private let fetch: Fetch
    private let storage: URL?
    private let now: () -> Date
    private var lastLoaded: Date?
    private var task: Task<Void, Never>?

    init(fetch: @escaping Fetch, storage: URL? = WorldFeed.defaultStorage, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.storage = storage
        self.now = now
        if let storage, let data = try? Data(contentsOf: storage),
           let saved = try? JSONDecoder().decode([ExplorePost].self, from: data), !saved.isEmpty {
            posts = saved
            isFromDisk = true
        }
    }

    convenience init(client: ExploreClient) {
        self.init(fetch: { try await client.posts(in: .world, cellDegrees: 0) })
    }

    nonisolated static var defaultStorage: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "world-feed.json")
    }

    /// Loads unless a load is running or the last one is younger than `maxAge`.
    func refreshIfNeeded(maxAge: TimeInterval = 60) {
        if let lastLoaded, now().timeIntervalSince(lastLoaded) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        phase = .loading
        task = Task { [fetch] in
            defer { task = nil }
            do {
                let result = try await fetch()
                // Newest first, whatever order the rows arrived in.
                posts = result.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                isFromDisk = false
                lastLoaded = now()
                phase = .loaded
                save()
            } catch {
                phase = .failed((error as? OnlineError) ?? .server(status: 0, message: nil))
            }
        }
    }

    /// Waits for the load in flight, if any (tests and the opening view).
    func settle() async { await task?.value }

    /// The user reported this piece or blocked its author: it leaves at once (spec: content-safety).
    func remove(where shouldRemove: (ExplorePost) -> Bool) {
        posts.removeAll(where: shouldRemove)
        save()
    }

    private func save() {
        guard let storage, let data = try? JSONEncoder().encode(posts) else { return }
        try? data.write(to: storage, options: .atomic)
    }
}

extension ExploreBounds {
    static let world = ExploreBounds(minLat: -90, minLng: -180, maxLat: 90, maxLng: 180)
}
