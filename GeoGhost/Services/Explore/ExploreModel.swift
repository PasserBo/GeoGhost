import Foundation
import MapKit
import Observation

/// What the world map shows for the visible region. Region changes are debounced, an older
/// request never overwrites a newer one, and recently loaded areas are served from memory.
@Observable
@MainActor
final class ExploreModel {
    typealias Fetch = @Sendable (ExploreBounds, Double) async throws -> [ExplorePost]

    private(set) var posts: [ExplorePost] = []
    private(set) var isLoading = false
    /// The last load failed (offline, server); the previous posts stay on screen.
    private(set) var error: OnlineError?
    /// At least one area has been loaded, so an empty list means "nothing here" rather than "not yet".
    private(set) var hasLoaded = false

    private struct Key: Hashable { let bounds: ExploreBounds; let cell: Double }
    private let fetch: Fetch
    private let debounce: Duration
    private let ttl: TimeInterval
    private let now: () -> Date
    private var cache: [Key: (at: Date, posts: [ExplorePost])] = [:]
    private var current: Task<Void, Never>?
    private var lastRegion: MKCoordinateRegion?

    init(fetch: @escaping Fetch, debounce: Duration = .milliseconds(350), ttl: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.debounce = debounce
        self.ttl = ttl
        self.now = now
    }

    convenience init(client: ExploreClient) {
        self.init(fetch: { bounds, cell in try await client.posts(in: bounds, cellDegrees: cell) })
    }

    func regionChanged(_ region: MKCoordinateRegion) {
        lastRegion = region
        load(region, delay: debounce, useCache: true)
    }

    /// Pull to refresh / retry after an error: skips the cache and the debounce.
    func reload() {
        guard let lastRegion else { return }
        load(lastRegion, delay: .zero, useCache: false)
    }

    /// The user blocked this author: their posts leave the map at once, and the area is fetched
    /// again so grid cells they stood in for are recounted (spec: content-safety › 屏蔽发布者).
    func authorBlocked(_ authorID: UUID) {
        posts.removeAll { $0.authorId == authorID }
        invalidate()
    }

    /// The user reported this post: it leaves their map at once and the area is fetched again
    /// (the server no longer returns it to them; spec: content-safety › 举报后自己不再看到).
    func postReported(_ postID: UUID) {
        posts.removeAll { $0.id == postID }
        invalidate()
    }

    /// What the user may see changed (blocked, unblocked, reported): cached areas are stale.
    func invalidate() {
        cache.removeAll()
        reload()
    }

    private func load(_ region: MKCoordinateRegion, delay: Duration, useCache: Bool) {
        let raw = ExploreBounds(region: region)
        let cell = ExploreGrid.cellDegrees(forLatitudeSpan: raw.latitudeSpan)
        let key = Key(bounds: raw.snapped(to: cell > 0 ? cell : 0.01), cell: cell)
        current?.cancel()
        if useCache, let hit = cache[key], now().timeIntervalSince(hit.at) < ttl {
            posts = hit.posts
            error = nil
            hasLoaded = true
            isLoading = false
            return
        }
        current = Task { [fetch] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
            }
            isLoading = true
            do {
                let result = try await fetch(key.bounds, key.cell)
                if Task.isCancelled { return }
                cache[key] = (now(), result)
                posts = result
                error = nil
                hasLoaded = true
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self.error = (error as? OnlineError) ?? .server(status: 0, message: nil)
            }
            isLoading = false
        }
    }
}
