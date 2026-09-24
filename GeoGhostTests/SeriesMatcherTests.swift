import CoreGraphics
import XCTest
@testable import GeoGhost

final class SeriesMatcherTests: XCTestCase {
    /// Vision's embedding models need the Neural Engine / GPU stack that the simulator lacks.
    private func featurePrint(_ image: CGImage) throws -> Data {
        do { return try FeaturePrintService.featurePrint(for: image) }
        catch let e as NSError where e.localizedDescription.contains("espresso") {
            throw XCTSkip("Vision feature prints are unavailable on this simulator; run on a device.")
        }
    }

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, pattern: Int) -> CGImage {
        let n = 128
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for i in 0..<pattern { ctx.fill(CGRect(x: 10 + i * 25, y: 10 + (i % 2) * 60, width: 18, height: 40)) }
        return ctx.makeImage()!
    }

    func testIdenticalImagesMatchAndDifferentOnesDoNot() throws {
        let a = try featurePrint(solid(1, 0.3, 0.1, pattern: 3))
        let a2 = try featurePrint(solid(1, 0.3, 0.1, pattern: 3))
        let b = try featurePrint(solid(0.1, 0.2, 0.9, pattern: 0))
        let same = FeaturePrintService.distance(a, a2)!
        let diff = FeaturePrintService.distance(a, b)!
        XCTAssertLessThan(same, 0.05)
        XCTAssertGreaterThan(diff, same)

        let matcher = SeriesMatcher()
        let sid = UUID()
        let verdict = matcher.evaluate(newPrint: a2, against: [
            .init(artworkID: UUID(), seriesID: nil, featurePrint: b),
            .init(artworkID: UUID(), seriesID: sid, featurePrint: a),
        ])
        guard case .match(_, let seriesID, _) = verdict else { return XCTFail("expected match, got \(verdict)") }
        XCTAssertEqual(seriesID, sid)
    }

    func testNoCandidatesIsNone() {
        XCTAssertEqual(SeriesMatcher().evaluate(newPrint: Data(), against: []), .none)
    }

    func testUnreadablePrintIsIgnored() throws {
        let a = try featurePrint(solid(1, 0.3, 0.1, pattern: 3))
        let v = SeriesMatcher().evaluate(newPrint: a, against: [.init(artworkID: UUID(), seriesID: nil, featurePrint: Data([1, 2, 3]))])
        XCTAssertEqual(v, .none)
    }
}
