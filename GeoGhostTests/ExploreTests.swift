import MapKit
import XCTest
@testable import GeoGhost

final class ExploreGeometryTests: XCTestCase {
    func testBoundsFromRegion() {
        let b = ExploreBounds(region: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.66, longitude: 139.70),
                                                         span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)))
        XCTAssertEqual(b.minLat, 35.61, accuracy: 1e-9)
        XCTAssertEqual(b.maxLat, 35.71, accuracy: 1e-9)
        XCTAssertEqual(b.minLng, 139.60, accuracy: 1e-9)
        XCTAssertEqual(b.maxLng, 139.80, accuracy: 1e-9)
    }

    func testRegionAcrossTheAntimeridian() {
        let b = ExploreBounds(region: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -17, longitude: 179),
                                                         span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 6)))
        XCTAssertEqual(b.minLng, 176, accuracy: 1e-9)
        XCTAssertEqual(b.maxLng, -178, accuracy: 1e-9)
        XCTAssertGreaterThan(b.minLng, b.maxLng)
    }

    func testWholeWorld() {
        let b = ExploreBounds(region: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 10),
                                                         span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 360)))
        XCTAssertEqual(b.minLng, -180)
        XCTAssertEqual(b.maxLng, 180)
        XCTAssertEqual(b.snapped(to: 32).minLng, -180)
    }

    /// Zoomed far out, a region just under 360° wide grows past ±180° on both sides when snapped;
    /// wrapping each edge on its own used to turn it into a thin band around the antimeridian.
    func testSnappingAWideRegionCoversTheWholeWorld() {
        let b = ExploreBounds(region: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                                         span: MKCoordinateSpan(latitudeDelta: 150, longitudeDelta: 340)))
        let s = b.snapped(to: 32)
        XCTAssertEqual(s.minLng, -180)
        XCTAssertEqual(s.maxLng, 180)
    }

    func testSnappingPastOneEdgeStillCoversTheRegion() {
        let b = ExploreBounds(minLat: 0, minLng: -170, maxLat: 10, maxLng: 10)
        let s = b.snapped(to: 32)
        // Grown west across the antimeridian: 168°…32° the long way round contains -170°…10°.
        XCTAssertEqual(s.minLng, 168)
        XCTAssertEqual(s.maxLng, 32)
        XCTAssertGreaterThan(s.minLng, s.maxLng)
    }

    func testGridSizeFollowsZoom() {
        XCTAssertEqual(ExploreGrid.cellDegrees(forLatitudeSpan: 0.02), 0, "zoomed in: individual posts")
        let city = ExploreGrid.cellDegrees(forLatitudeSpan: 0.2)
        let country = ExploreGrid.cellDegrees(forLatitudeSpan: 10)
        XCTAssertGreaterThan(city, 0)
        XCTAssertGreaterThan(country, city)
        // Powers of two, so slightly different zooms share the same cells.
        XCTAssertEqual(ExploreGrid.cellDegrees(forLatitudeSpan: 0.2), ExploreGrid.cellDegrees(forLatitudeSpan: 0.18))
        XCTAssertEqual(log2(city).rounded(), log2(city))
    }

    func testSnappingCoversTheOriginalBounds() {
        let b = ExploreBounds(minLat: 35.61, minLng: 139.61, maxLat: 35.71, maxLng: 139.79)
        let s = b.snapped(to: 0.05)
        XCTAssertLessThanOrEqual(s.minLat, b.minLat)
        XCTAssertGreaterThanOrEqual(s.maxLat, b.maxLat)
        XCTAssertLessThanOrEqual(s.minLng, b.minLng)
        XCTAssertGreaterThanOrEqual(s.maxLng, b.maxLng)
    }

    func testDecodesServerRows() throws {
        let json = Data("""
        [{"id":"8d0e7a50-3c55-4f43-9a35-7b1f2f7b8a11","author_id":"1d6a6a0e-1111-4c3e-8f00-1234567890ab","author_nickname":"sim",
          "kind":"sticker","lat":35.659,"lng":139.701,"locality":"Shibuya","country_code":"JP","captured_on":"2026-11-12",
          "width":1024,"height":512,"image_key":"posts/x/full.heic","thumb_key":"posts/x/thumb.heic","like_count":3,
          "published_at":"2026-11-12T03:04:05.123+00:00","cell_count":1}]
        """.utf8)
        let rows = try OnlineHTTP.decoder.decode([ExplorePost].self, from: json)
        XCTAssertEqual(rows.first?.artworkKind, .sticker)
        XCTAssertEqual(rows.first?.capturedOn, "2026-11-12")
        XCTAssertEqual(rows.first?.likeCount, 3)
        XCTAssertNotNil(rows.first?.publishedAt)
    }
}

@MainActor
final class ExploreModelTests: XCTestCase {
    private actor Recorder {
        var calls: [(ExploreBounds, Double)] = []
        var fail: OnlineError?
        func record(_ b: ExploreBounds, _ c: Double) throws -> [ExplorePost] {
            calls.append((b, c))
            if let fail { throw fail }
            return []
        }
        func setFail(_ e: OnlineError?) { fail = e }
    }

    private func region(_ lat: Double, _ lng: Double, span: Double = 0.2) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    /// Waits until `condition` holds (up to two seconds), so timing on a busy machine doesn't matter.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testRapidPansSendOneRequestForTheLastRegion() async {
        let recorder = Recorder()
        let model = ExploreModel(fetch: { b, c in try await recorder.record(b, c) }, debounce: .milliseconds(50))
        model.regionChanged(region(35.0, 139.0))
        model.regionChanged(region(36.0, 139.0))
        model.regionChanged(region(37.0, 139.0))
        await settle()
        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertGreaterThan(calls.first?.0.minLat ?? 0, 36.5)
    }

    func testSmallPanReusesCachedArea() async {
        let recorder = Recorder()
        let model = ExploreModel(fetch: { b, c in try await recorder.record(b, c) }, debounce: .milliseconds(10))
        model.regionChanged(region(35.66, 139.70))
        await waitUntil { await recorder.calls.count == 1 && !model.isLoading }
        model.regionChanged(region(35.6601, 139.7001))
        await settle()
        let count = await recorder.calls.count
        XCTAssertEqual(count, 1)

        model.reload()
        await waitUntil { await recorder.calls.count == 2 }
        let afterReload = await recorder.calls.count
        XCTAssertEqual(afterReload, 2, "reload skips the cache")
    }

    func testFailureIsReportedAndClearedOnSuccess() async {
        let recorder = Recorder()
        await recorder.setFail(.offline)
        let model = ExploreModel(fetch: { b, c in try await recorder.record(b, c) }, debounce: .milliseconds(10))
        model.regionChanged(region(35.66, 139.70))
        await waitUntil { model.error != nil }
        XCTAssertEqual(model.error, .offline)
        XCTAssertFalse(model.isLoading)

        await recorder.setFail(nil)
        model.reload()
        await waitUntil { model.error == nil }
        XCTAssertNil(model.error)
    }
}
