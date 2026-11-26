import CoreLocation
import Foundation
import MapKit

/// The two prompts that start from the user's own collection: a pointer to the area where their
/// pieces would be the first public ones, and an invitation shown while they look at such an area.
/// Positions come from the collection only; the app never reads the user's live location for this.
enum OwnAreaPrompts {
    /// One of the user's own pieces, as much of it as the prompts need.
    struct Piece: Equatable, Sendable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let placeName: String?
        let date: Date
        let state: PublishState

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    // Starting values, to be tuned after use on a device (proposal › 提示的设计).
    static let homeRadiusMeters = 5_000.0
    static let pointerMinimumPieces = 3
    static let pointerEmptyRadiusMeters = 50_000.0
    static let invitationMaximumSpan = 0.3

    struct Pointer: Equatable, Sendable {
        let placeName: String?
        let pieceCount: Int
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// Where the user last collected something with a location.
    static func anchor(of pieces: [Piece]) -> Piece? { pieces.max { $0.date < $1.date } }

    /// The pointer, when the user has enough unshared pieces around where they collect and no
    /// public piece is anywhere near.
    static func pointer(pieces: [Piece], posts: [ExplorePost]) -> Pointer? {
        guard let anchor = anchor(of: pieces) else { return nil }
        let around = pieces.filter { $0.state == .unpublished && WorldCamera.distance($0.coordinate, anchor.coordinate) <= homeRadiusMeters }
        guard around.count >= pointerMinimumPieces else { return nil }
        guard !posts.contains(where: { WorldCamera.distance($0.coordinate, anchor.coordinate) <= pointerEmptyRadiusMeters }) else { return nil }
        return Pointer(placeName: mostCommonPlace(in: around), pieceCount: around.count, latitude: anchor.latitude, longitude: anchor.longitude)
    }

    enum Invitation: Equatable, Sendable {
        /// These pieces of the user's, newest first, could be the first public ones here.
        case share([UUID])
        /// Everything the user has here is already waiting for review.
        case inReview(Int)
    }

    /// The invitation for the area on screen: only at city scale or closer, only where no public
    /// piece is shown, and only when the user has pieces there.
    static func invitation(pieces: [Piece], publicCount: Int, region: MKCoordinateRegion) -> Invitation? {
        guard publicCount == 0, region.span.latitudeDelta <= invitationMaximumSpan else { return nil }
        let here = pieces.filter { contains(region, $0.coordinate) }.sorted { $0.date > $1.date }
        let unshared = here.filter { $0.state == .unpublished }
        if !unshared.isEmpty { return .share(unshared.map(\.id)) }
        let waiting = here.filter { $0.state == .pending || $0.state == .uploading }
        return waiting.isEmpty ? nil : .inReview(waiting.count)
    }

    static func contains(_ region: MKCoordinateRegion, _ c: CLLocationCoordinate2D) -> Bool {
        var dLon = abs(c.longitude - region.center.longitude)
        if dLon > 180 { dLon = 360 - dLon }
        return abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta / 2 && dLon <= region.span.longitudeDelta / 2
    }

    /// The name most of these pieces share, the part before the comma ("高円寺南, 杉並区" → "高円寺南"
    /// would be too local, so the last part — the city or ward — is used).
    static func mostCommonPlace(in pieces: [Piece]) -> String? {
        var counts: [String: Int] = [:]
        for piece in pieces {
            guard let name = piece.placeName?.split(separator: ",").last.map({ $0.trimmingCharacters(in: .whitespaces) }), !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    // MARK: Dismissing the pointer

    /// Remembers that the pointer was closed: quiet for a week, and after three times quiet until
    /// the user has collected more around there.
    struct PointerMemory: Equatable, Sendable {
        static let quietInterval: TimeInterval = 7 * 86_400
        static let maximumDismissals = 3

        var dismissals = 0
        var lastDismissed: Date?
        var pieceCountAtLastDismissal = 0

        func allows(_ pointer: Pointer, now: Date) -> Bool {
            if dismissals >= Self.maximumDismissals { return pointer.pieceCount > pieceCountAtLastDismissal }
            if let lastDismissed, now.timeIntervalSince(lastDismissed) < Self.quietInterval { return false }
            return true
        }

        mutating func dismiss(_ pointer: Pointer, now: Date) {
            dismissals += 1
            lastDismissed = now
            pieceCountAtLastDismissal = pointer.pieceCount
        }

        private static let key = "worldMapPointerMemory"

        static func load(from defaults: UserDefaults = .standard) -> PointerMemory {
            guard let values = defaults.dictionary(forKey: key) else { return PointerMemory() }
            return PointerMemory(dismissals: values["dismissals"] as? Int ?? 0, lastDismissed: values["last"] as? Date,
                                 pieceCountAtLastDismissal: values["pieces"] as? Int ?? 0)
        }

        func save(to defaults: UserDefaults = .standard) {
            var values: [String: Any] = ["dismissals": dismissals, "pieces": pieceCountAtLastDismissal]
            if let lastDismissed { values["last"] = lastDismissed }
            defaults.set(values, forKey: Self.key)
        }
    }
}

extension OwnAreaPrompts.Piece {
    init?(_ artwork: Artwork) {
        guard let coordinate = artwork.coordinate else { return nil }
        self.init(id: artwork.id, latitude: coordinate.latitude, longitude: coordinate.longitude,
                  placeName: artwork.placeName, date: artwork.displayDate, state: artwork.publishState)
    }
}
