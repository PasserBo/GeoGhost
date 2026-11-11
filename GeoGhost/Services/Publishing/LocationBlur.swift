import CoreLocation

/// Public posts show where a piece was found only to the nearest block (about 100 m), so a
/// collection never reveals someone's exact routes. The server snaps again with the same formula
/// (design.md §4); snapping is idempotent, so both agree.
enum LocationBlur {
    static let gridDegrees = 0.001

    static func snap(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: snap(coordinate.latitude), longitude: snap(coordinate.longitude))
    }

    /// `round(value / grid) * grid`, then trimmed to three decimals so the JSON stays exact.
    static func snap(_ degrees: Double) -> Double {
        let cells = (degrees / gridDegrees).rounded(.toNearestOrAwayFromZero)
        return (cells * gridDegrees * 1000).rounded() / 1000
    }
}
