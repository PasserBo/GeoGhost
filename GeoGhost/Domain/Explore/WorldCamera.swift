import CoreLocation
import Foundation
import MapKit

/// Where the world map opens, and how its camera travels between places.
enum WorldCamera {
    /// Public pieces within this distance of where the user collects count as "near them".
    static let nearbyMeters = 50_000.0
    static let minimumSpan = 0.02
    static let maximumSpan = 0.6

    struct Opening: Equatable {
        let region: MKCoordinateRegion
        /// The map opened on pieces near where the user collects (false: on the busiest area anywhere).
        let isNearUser: Bool

        static func == (l: Opening, r: Opening) -> Bool {
            l.isNearUser == r.isNearUser && l.region.center.latitude == r.region.center.latitude
                && l.region.center.longitude == r.region.center.longitude
                && l.region.span.latitudeDelta == r.region.span.latitudeDelta && l.region.span.longitudeDelta == r.region.span.longitudeDelta
        }
    }

    /// Frames the public pieces near `anchor` (where the user last collected something with a
    /// location). With no anchor, or nothing near it, frames the area with the most pieces.
    /// Nil when there are no public pieces at all.
    static func opening(posts: [ExplorePost], anchor: CLLocationCoordinate2D?) -> Opening? {
        guard !posts.isEmpty else { return nil }
        if let anchor {
            let near = posts.filter { distance($0.coordinate, anchor) <= nearbyMeters }
            if !near.isEmpty { return Opening(region: region(fitting: near.map(\.coordinate)), isNearUser: true) }
        }
        // The busiest area: the piece with the most neighbours, the newest winning a tie.
        var best: [ExplorePost] = []
        for post in posts {
            let neighbours = posts.filter { distance($0.coordinate, post.coordinate) <= nearbyMeters }
            if neighbours.count > best.count { best = neighbours }
        }
        return Opening(region: region(fitting: best.map(\.coordinate)), isNearUser: false)
    }

    /// The region holding every coordinate with room around them, never closer than a few blocks
    /// and never wider than a metropolitan area.
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else { return MKCoordinateRegion(.world) }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        func span(_ delta: Double) -> Double { min(maximumSpan, max(minimumSpan, delta * 1.5)) }
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span(maxLat - minLat), longitudeDelta: span(maxLon - minLon)))
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: Travel

    /// How the camera gets somewhere. Distance is counted in screens, not kilometres: five
    /// kilometres is dozens of screens at street level and a fraction of one at country level.
    enum Travel: Equatable {
        /// Less than a screen away: slide there.
        case pan
        /// A few screens away: one longer, eased move.
        case fly
        /// Far away: cut, since an animation would cross a blank map at speed.
        case cut

        var duration: TimeInterval {
            switch self {
            case .pan: 0.35
            case .fly: 1.0
            case .cut: 0
            }
        }
    }

    static let flyScreens = 8.0
    /// Changing the zoom by more than this factor is a cut, however near the target is.
    static let flyZoomFactor = 8.0

    static func travel(from visible: MKCoordinateRegion, to target: MKCoordinateRegion, reduceMotion: Bool) -> Travel {
        guard !reduceMotion, visible.span.latitudeDelta > 0, visible.span.longitudeDelta > 0 else { return .cut }
        var dLon = abs(target.center.longitude - visible.center.longitude)
        if dLon > 180 { dLon = 360 - dLon }
        let screens = max(abs(target.center.latitude - visible.center.latitude) / visible.span.latitudeDelta, dLon / visible.span.longitudeDelta)
        let zoom = max(target.span.latitudeDelta / visible.span.latitudeDelta, visible.span.latitudeDelta / max(target.span.latitudeDelta, 1e-9))
        if screens > flyScreens || zoom > flyZoomFactor { return .cut }
        return screens < 1 && zoom < 2 ? .pan : .fly
    }
}
