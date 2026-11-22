import CoreLocation
import XCTest
@testable import GeoGhost

final class SeriesStatsTests: XCTestCase {
    private func encounter(_ day: Int, _ latitude: Double? = nil, _ longitude: Double? = nil, place: String? = nil,
                           locality: String? = nil, country: String? = "JP") -> SeriesStats.Encounter {
        SeriesStats.Encounter(latitude: latitude, longitude: longitude, placeName: place, localityName: locality,
                              countryCode: latitude == nil ? nil : country, date: Date(timeIntervalSince1970: Double(day) * 86_400 + 3_600))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testFarthestPairAcrossCities() {
        // Koenji, Shimokitazawa, Osaka — given out of order.
        let stats = SeriesStats(encounters: [
            encounter(97, 34.7077, 135.5058, place: "中崎町", locality: "大阪市"),
            encounter(0, 35.7023, 139.6497, place: "高円寺南", locality: "杉並区"),
            encounter(47, 35.6614, 139.6680, place: "北沢", locality: "世田谷区"),
        ])
        XCTAssertEqual(stats.encounterCount, 3)
        XCTAssertEqual(stats.placeCount, 3)
        XCTAssertEqual(stats.stops.map(\.placeName), ["高円寺南", "北沢", "中崎町"], "Stops follow the dates")
        // Shimokitazawa lies a little east of Koenji, so it is the one farthest from Osaka.
        XCTAssertEqual(stats.farthest?.first, 1)
        XCTAssertEqual(stats.farthest?.second, 2)
        XCTAssertEqual(stats.distanceMeters ?? 0, 392_000, accuracy: 6_000)
        XCTAssertTrue(stats.isCrossCity)
        XCTAssertEqual(stats.spanDays(calendar: utc), 98)
        XCTAssertEqual(stats.countryCode, "JP")
        XCTAssertEqual(SeriesShareCards.leads(for: stats), [.distance, .encounters])
    }

    func testSameCityLeadsWithEncounters() {
        let stats = SeriesStats(encounters: [
            encounter(0, 35.7023, 139.6497, locality: "杉並区"),
            encounter(3, 35.6614, 139.6680, locality: "世田谷区"),
        ])
        XCTAssertFalse(stats.isCrossCity, "Two Tokyo wards are one city, whatever their names say")
        XCTAssertNotNil(stats.distanceMeters)
        XCTAssertEqual(SeriesShareCards.leads(for: stats), [.encounters, .distance])
    }

    func testPositionsAreSnappedBeforeMeasuring() {
        // 30 m apart: the same ~100 m cell, so the card must not claim a distance.
        let stats = SeriesStats(encounters: [encounter(0, 35.70231, 139.64972), encounter(1, 35.70249, 139.64994)])
        XCTAssertEqual(stats.stops[0].latitude, 35.702)
        XCTAssertEqual(stats.stops[0].longitude, 139.650)
        XCTAssertEqual(stats.stops[0], stats.stops[1])
        XCTAssertNil(stats.distanceMeters)
        XCTAssertEqual(SeriesShareCards.leads(for: stats), [.encounters])
    }

    func testNoLocations() {
        let stats = SeriesStats(encounters: [encounter(0), encounter(18)])
        XCTAssertEqual(stats.encounterCount, 2)
        XCTAssertEqual(stats.placeCount, 0)
        XCTAssertTrue(stats.stops.isEmpty)
        XCTAssertNil(stats.farthest)
        XCTAssertNil(stats.countryCode)
        XCTAssertEqual(stats.spanDays(calendar: utc), 19)
        XCTAssertEqual(SeriesShareCards.leads(for: stats), [.encounters])
    }

    func testCountryIsUnsetAcrossBorders() {
        let stats = SeriesStats(encounters: [encounter(0, 35.70, 139.65), encounter(1, 37.57, 126.98, country: "KR")])
        XCTAssertNil(stats.countryCode)
    }

    func testDistanceText() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(DistanceText.metric(398_400, locale: us), "398 km")
        XCTAssertEqual(DistanceText.metric(2_140, locale: us), "2.1 km")
        XCTAssertEqual(DistanceText.metric(830, locale: us), "850 m")
        XCTAssertEqual(DistanceText.metric(1_234_000, locale: us), "1,234 km")
        XCTAssertEqual(DistanceText.imperial(398_400, locale: us), "248 mi")
        XCTAssertEqual(DistanceText.imperial(2_140, locale: us), "1.3 mi")
        XCTAssertEqual(DistanceText.imperial(100, locale: us), "0.1 mi")
    }

    func testMapRegionHasAMinimumSize() {
        let region = RouteMapSnapshotter.region(for: [CLLocationCoordinate2D(latitude: 35.702, longitude: 139.650)])
        XCTAssertEqual(region.span.latitudeDelta, RouteMapSnapshotter.minimumLatitudeSpan)
        let wide = RouteMapSnapshotter.region(for: [.init(latitude: 35.702, longitude: 139.650), .init(latitude: 34.708, longitude: 135.506)])
        XCTAssertEqual(wide.span.longitudeDelta, (139.650 - 135.506) * 1.9, accuracy: 0.001)
        XCTAssertEqual(wide.center.latitude, 35.205, accuracy: 0.001)
    }
}
