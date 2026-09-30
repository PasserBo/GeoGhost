import CoreLocation
import Foundation
import SwiftData

/// One collected piece: a single encounter with a sticker, graffiti, mural…
@Model
final class Artwork {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var capturedAt: Date?
    var capturedAtIsEstimated: Bool = false

    var kindRaw: String = ArtworkKind.sticker.rawValue
    var kindIsAutoDetected: Bool = false
    var kindIsUserSet: Bool = false

    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var heading: Double?
    var locationSourceRaw: String = LocationSource.none.rawValue
    var placeName: String?
    var localityName: String?
    var countryCode: String?

    var originalImageID: String = "original.heic"
    var cutoutImageID: String = "cutout.png"
    var thumbnailImageID: String = "thumb.png"
    var imagePixelWidth: Int = 0
    var imagePixelHeight: Int = 0

    /// Normalized (0…1) rect of the cutout inside the original image.
    var cutoutX: Double = 0
    var cutoutY: Double = 0
    var cutoutW: Double = 1
    var cutoutH: Double = 1
    var segmentationModeRaw: String = SegmentationMode.auto.rawValue

    @Attribute(.externalStorage) var featurePrint: Data?
    var dominantColorHex: String?
    var deviceModel: String?
    var lensModel: String?

    var note: String = ""
    var isFavorite: Bool = false
    var visibilityRaw: String = Visibility.privateOnly.rawValue

    var isSeriesManuallyAssigned: Bool = false
    var series: ArtSeries?
    @Relationship(inverse: \Tag.artworks) var tags: [Tag]? = []

    init(id: UUID = UUID(), kind: ArtworkKind = .sticker) {
        self.id = id
        self.kindRaw = kind.rawValue
    }
}

// MARK: - Typed accessors

extension Artwork {
    var kind: ArtworkKind {
        get { ArtworkKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var locationSource: LocationSource {
        get { LocationSource(rawValue: locationSourceRaw) ?? .none }
        set { locationSourceRaw = newValue.rawValue }
    }

    var segmentationMode: SegmentationMode {
        get { SegmentationMode(rawValue: segmentationModeRaw) ?? .auto }
        set { segmentationModeRaw = newValue.rawValue }
    }

    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .privateOnly }
        set { visibilityRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let c = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }

    var cutoutRect: CGRect {
        get { CGRect(x: cutoutX, y: cutoutY, width: cutoutW, height: cutoutH) }
        set { cutoutX = newValue.minX; cutoutY = newValue.minY; cutoutW = newValue.width; cutoutH = newValue.height }
    }

    /// Best available timestamp for display and sorting.
    var displayDate: Date { capturedAt ?? createdAt }

    var tagList: [Tag] { tags ?? [] }

    /// The capture metadata this artwork was saved with (for re-editing its photo).
    var captureMetadata: CaptureMetadata {
        var m = CaptureMetadata()
        m.capturedAt = capturedAt; m.capturedAtIsEstimated = capturedAtIsEstimated
        m.latitude = latitude; m.longitude = longitude; m.horizontalAccuracy = horizontalAccuracy
        m.altitude = altitude; m.heading = heading; m.locationSource = locationSource
        m.deviceModel = deviceModel; m.lensModel = lensModel
        m.pixelWidth = imagePixelWidth; m.pixelHeight = imagePixelHeight
        return m
    }

    func apply(_ metadata: CaptureMetadata) {
        capturedAt = metadata.capturedAt
        capturedAtIsEstimated = metadata.capturedAtIsEstimated
        latitude = metadata.latitude
        longitude = metadata.longitude
        horizontalAccuracy = metadata.horizontalAccuracy
        altitude = metadata.altitude
        heading = metadata.heading
        locationSource = metadata.coordinate == nil ? .none : metadata.locationSource
        deviceModel = metadata.deviceModel
        lensModel = metadata.lensModel
        imagePixelWidth = metadata.pixelWidth
        imagePixelHeight = metadata.pixelHeight
    }
}
