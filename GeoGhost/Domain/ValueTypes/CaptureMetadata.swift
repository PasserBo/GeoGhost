import CoreLocation
import Foundation

/// Everything we know about a photo before it becomes an `Artwork`.
/// Assembled from EXIF (imports) or live sensors (in-app camera).
struct CaptureMetadata: Sendable, Equatable {
    var capturedAt: Date?
    var capturedAtIsEstimated: Bool = false
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var heading: Double?
    var locationSource: LocationSource = .none
    var deviceModel: String?
    var lensModel: String?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)),
              !(latitude == 0 && longitude == 0) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    /// Fill any gaps in `self` with values from `other` (used to layer live GPS over EXIF).
    func merging(fallback other: CaptureMetadata) -> CaptureMetadata {
        var merged = self
        if merged.capturedAt == nil { merged.capturedAt = other.capturedAt; merged.capturedAtIsEstimated = other.capturedAtIsEstimated }
        if merged.coordinate == nil, other.coordinate != nil {
            merged.latitude = other.latitude
            merged.longitude = other.longitude
            merged.horizontalAccuracy = other.horizontalAccuracy
            merged.altitude = other.altitude
            merged.locationSource = other.locationSource
        }
        if merged.heading == nil { merged.heading = other.heading }
        if merged.deviceModel == nil { merged.deviceModel = other.deviceModel }
        if merged.lensModel == nil { merged.lensModel = other.lensModel }
        if merged.pixelWidth == 0 { merged.pixelWidth = other.pixelWidth; merged.pixelHeight = other.pixelHeight }
        return merged
    }
}
