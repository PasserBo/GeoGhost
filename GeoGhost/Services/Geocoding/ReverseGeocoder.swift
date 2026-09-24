import CoreLocation
import Foundation

struct PlaceInfo: Sendable, Equatable {
    /// Short, human label: "Shibuya, Tokyo" / "Kreuzberg, Berlin".
    var placeName: String
    var locality: String?
    var countryCode: String?
}

/// Reverse geocoding with a small in-memory cache and Apple's rate limit in mind.
actor ReverseGeocoder {
    static let shared = ReverseGeocoder()
    private let geocoder = CLGeocoder()
    private var cache: [String: PlaceInfo] = [:]

    func lookup(_ coordinate: CLLocationCoordinate2D) async -> PlaceInfo? {
        // ~100 m cache cells.
        let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        if let hit = cache[key] { return hit }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var attempt = 0
        while attempt < 3 {
            do {
                let marks = try await geocoder.reverseGeocodeLocation(location)
                guard let p = marks.first else { return nil }
                let info = Self.placeInfo(from: p)
                cache[key] = info
                return info
            } catch {
                attempt += 1
                try? await Task.sleep(for: .seconds(Double(1 << attempt)))
            }
        }
        return nil
    }

    static func placeInfo(from p: CLPlacemark) -> PlaceInfo {
        let area = p.subLocality ?? p.thoroughfare
        let city = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea
        let parts = [area, city].compactMap { $0 }.filter { !$0.isEmpty }
        let name: String
        if parts.isEmpty { name = p.country ?? "" }
        else if parts.count == 2 && parts[0] == parts[1] { name = parts[0] }
        else { name = parts.joined(separator: ", ") }
        return PlaceInfo(placeName: name, locality: city, countryCode: p.isoCountryCode)
    }
}
