import CoreLocation
import Foundation
import MapKit

/// One public post, or one grid cell standing for several (design.md §10 `explore` columns).
struct ExplorePost: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let authorId: UUID
    let authorNickname: String?
    let kind: String
    let lat: Double
    let lng: Double
    let locality: String?
    let countryCode: String?
    /// The server's calendar day (`yyyy-MM-dd`), kept as text so no time zone shifts it.
    let capturedOn: String?
    let width: Int?
    let height: Int?
    let imageKey: String?
    let thumbKey: String?
    let likeCount: Int
    let publishedAt: Date?
    /// How many posts this row stands for: 1 in list mode, the cell's count in grid mode.
    let cellCount: Int

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var artworkKind: ArtworkKind { ArtworkKind(rawValue: kind) ?? .other }
}

/// The visible part of the map, as the server's `explore` wants it. When the region crosses the
/// 180° meridian, `minLng > maxLng` (the server handles that case).
struct ExploreBounds: Equatable, Hashable, Sendable {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double

    init(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) {
        self.minLat = minLat; self.minLng = minLng; self.maxLat = maxLat; self.maxLng = maxLng
    }

    init(region: MKCoordinateRegion) {
        let halfLat = region.span.latitudeDelta / 2, halfLng = min(region.span.longitudeDelta, 360) / 2
        minLat = max(-90, region.center.latitude - halfLat)
        maxLat = min(90, region.center.latitude + halfLat)
        if halfLng >= 180 {
            minLng = -180; maxLng = 180
        } else {
            minLng = Self.wrap(region.center.longitude - halfLng)
            maxLng = Self.wrap(region.center.longitude + halfLng)
        }
    }

    var latitudeSpan: Double { maxLat - minLat }

    /// Grows the bounds to whole multiples of `step` so small pans reuse the same request.
    func snapped(to step: Double) -> ExploreBounds {
        guard step > 0 else { return self }
        func down(_ v: Double) -> Double { (v / step).rounded(.down) * step }
        func up(_ v: Double) -> Double { (v / step).rounded(.up) * step }
        if minLng == -180, maxLng == 180 {
            return ExploreBounds(minLat: max(-90, down(minLat)), minLng: -180, maxLat: min(90, up(maxLat)), maxLng: 180)
        }
        return ExploreBounds(minLat: max(-90, down(minLat)), minLng: Self.wrap(down(minLng)),
                             maxLat: min(90, up(maxLat)), maxLng: Self.wrap(up(maxLng)))
    }

    static func wrap(_ lng: Double) -> Double {
        var v = lng.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 } else if v < -180 { v += 360 }
        return v
    }
}

/// How coarse the grid is for a given zoom. Zoomed in far enough, posts come back one by one.
enum ExploreGrid {
    /// Below this latitude span (about 3 km) the map shows individual posts.
    static let listModeSpan = 0.03
    /// About 8 cells across the visible height, rounded to a power of two so nearby zooms share cells.
    static func cellDegrees(forLatitudeSpan span: Double) -> Double {
        guard span >= listModeSpan else { return 0 }
        let raw = span / 8
        return pow(2, (log2(raw)).rounded(.up))
    }
}

/// Reads the world map (design.md §5 `explore`). Works without an identity; when the user has one,
/// posts by people they blocked are left out by the server.
struct ExploreClient: Sendable {
    let services: OnlineServices

    func posts(in bounds: ExploreBounds, cellDegrees: Double) async throws -> [ExplorePost] {
        struct Params: Encodable, Sendable {
            let minLat: Double, minLng: Double, maxLat: Double, maxLng: Double, cellDeg: Double
        }
        return try await services.database.rpc("explore", Params(minLat: bounds.minLat, minLng: bounds.minLng, maxLat: bounds.maxLat,
                                                                 maxLng: bounds.maxLng, cellDeg: cellDegrees),
                                                identity: .ifPresent)
    }
}
