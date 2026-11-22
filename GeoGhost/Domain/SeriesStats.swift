import CoreLocation
import Foundation

/// The numbers a series can show about itself, worked out from its encounters.
///
/// Positions are snapped to the same ~100 m grid as published pieces before anything is measured,
/// so nothing derived from them (distances, a map, a card) is more precise than what the app
/// already makes public.
struct SeriesStats: Equatable, Sendable {
    /// One sighting of the design, as much of it as the numbers need.
    struct Encounter: Equatable, Sendable {
        var latitude: Double?
        var longitude: Double?
        var placeName: String?
        var localityName: String?
        var countryCode: String?
        var date: Date
    }

    /// An encounter that has a position, in the order they happened.
    struct Stop: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let placeName: String?

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// The two stops farthest from each other.
    struct Farthest: Equatable, Sendable {
        let first: Int
        let second: Int
        let meters: Double
    }

    /// Farthest stops at least this far apart count as different cities. Place names can't tell:
    /// each of Tokyo's wards is its own locality.
    static let crossCityMeters = 30_000.0
    /// Below this the snapped positions say nothing about distance.
    static let minimumMeaningfulMeters = 100.0

    let encounterCount: Int
    let placeCount: Int
    let firstSeen: Date?
    let lastSeen: Date?
    let stops: [Stop]
    let farthest: Farthest?
    /// Set when every stop is in the same country.
    let countryCode: String?

    init(encounters: [Encounter]) {
        let ordered = encounters.sorted { $0.date < $1.date }
        encounterCount = ordered.count
        var seen = Set<String>()
        placeCount = ordered.compactMap { $0.localityName ?? $0.placeName }.filter { seen.insert($0).inserted }.count
        firstSeen = ordered.first?.date
        lastSeen = ordered.last?.date

        let located = ordered.filter { $0.latitude != nil && $0.longitude != nil }
        stops = located.map { e in
            let snapped = LocationBlur.snap(CLLocationCoordinate2D(latitude: e.latitude!, longitude: e.longitude!))
            return Stop(latitude: snapped.latitude, longitude: snapped.longitude, placeName: e.placeName)
        }
        let codes = Set(located.map(\.countryCode))
        countryCode = codes.count == 1 ? (codes.first ?? nil) : nil

        // A series has a handful of encounters, so comparing every pair is fine.
        var best: Farthest?
        for i in stops.indices {
            let a = CLLocation(latitude: stops[i].latitude, longitude: stops[i].longitude)
            for j in stops.indices where j > i {
                let meters = a.distance(from: CLLocation(latitude: stops[j].latitude, longitude: stops[j].longitude))
                if meters > (best?.meters ?? 0) { best = Farthest(first: i, second: j, meters: meters) }
            }
        }
        farthest = best
    }

    /// The farthest distance, when it is large enough to mean something.
    var distanceMeters: Double? {
        guard let farthest, farthest.meters >= Self.minimumMeaningfulMeters else { return nil }
        return farthest.meters
    }

    var isCrossCity: Bool { (farthest?.meters ?? 0) >= Self.crossCityMeters }

    /// Calendar days from the first encounter to the last, counting both.
    func spanDays(calendar: Calendar = .current) -> Int? {
        guard let firstSeen, let lastSeen else { return nil }
        return (calendar.dateComponents([.day], from: firstSeen, to: lastSeen).day ?? 0) + 1
    }
}

extension SeriesStats {
    init(series: ArtSeries) {
        self.init(encounters: series.members.map { a in
            Encounter(latitude: a.coordinate?.latitude, longitude: a.coordinate?.longitude, placeName: a.placeName,
                      localityName: a.localityName, countryCode: a.countryCode, date: a.displayDate)
        })
    }
}

/// Distances as short text. Both systems are available because a shared card is read by people
/// who aren't in the sharer's region.
enum DistanceText {
    /// "398 km", "2.1 km", "850 m".
    static func metric(_ meters: Double, locale: Locale = .current) -> String {
        let km = meters / 1000
        if km >= 100 { return "\(km.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))) km" }
        if km >= 1 { return "\(km.formatted(.number.precision(.fractionLength(1)).locale(locale))) km" }
        let rounded = max(50, (meters / 50).rounded() * 50)
        return "\(rounded.formatted(.number.precision(.fractionLength(0)).locale(locale))) m"
    }

    /// "247 mi", "1.3 mi", "0.5 mi".
    static func imperial(_ meters: Double, locale: Locale = .current) -> String {
        let miles = meters / 1609.344
        if miles >= 100 { return "\(miles.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))) mi" }
        return "\(max(0.1, miles).formatted(.number.precision(.fractionLength(1)).locale(locale))) mi"
    }
}
