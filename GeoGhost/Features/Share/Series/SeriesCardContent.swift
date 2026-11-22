import SwiftUI
import UIKit

/// Everything a series card shows, captured up front so drawing it doesn't touch SwiftData.
struct SeriesCardContent {
    /// Above this the map already shows most of a country, and a locator would repeat it.
    static let locatorMaximumMeters = 250_000.0

    /// Which of the user's series this is, counting from the first one they started.
    var number: Int
    /// Empty when the series has no name yet.
    var title: String
    var kind: ArtworkKind
    var picture: UIImage
    /// The picture is the original photo rather than the cutout.
    var pictureIsPhoto = false
    var stats: SeriesStats
    var map: RouteMapImage?
    var countryOutline: CountryOutline?

    /// The country outline, when the map is local enough to need one.
    var locator: CountryOutline? {
        guard let countryOutline, (stats.farthest?.meters ?? 0) < Self.locatorMaximumMeters else { return nil }
        return countryOutline
    }
}
