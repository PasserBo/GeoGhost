import CoreGraphics
import SwiftData
import UIKit
import XCTest
@testable import GeoGhost

final class SeriesMatcherTests: XCTestCase {
    /// A busy synthetic "sticker": random text glyphs, irregular polygons and discs on white — plenty of
    /// distinctive corners (axis-aligned rectangles alone give ambiguous right-angle corners).
    private func sticker(seed: Int, size n: Int = 420) -> CGImage {
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        var rng = SplitMix64(seed: UInt64(seed))
        func r(_ m: Int) -> Int { Int(rng.next() % UInt64(m)) }
        for _ in 0..<7 {
            ctx.setFillColor(CGColor(red: CGFloat(r(100)) / 100, green: CGFloat(r(100)) / 100, blue: CGFloat(r(100)) / 100, alpha: 1))
            let cx = 50 + r(n - 100), cy = 50 + r(n - 100), k = 3 + r(4)
            let path = CGMutablePath()
            for i in 0..<k {
                let a = CGFloat(i) / CGFloat(k) * 2 * .pi + CGFloat(r(60)) / 100
                let rad = CGFloat(20 + r(50))
                let pt = CGPoint(x: CGFloat(cx) + cos(a) * rad, y: CGFloat(cy) + sin(a) * rad)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath(); ctx.addPath(path); ctx.fillPath()
        }
        UIGraphicsPushContext(ctx)
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<10 {
            let word = String((0..<(2 + r(4))).map { _ in letters[r(letters.count)] })
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: CGFloat(22 + r(30))), .foregroundColor: UIColor(white: CGFloat(r(30)) / 100, alpha: 1)]
            ctx.saveGState(); ctx.translateBy(x: CGFloat(30 + r(n - 120)), y: CGFloat(30 + r(n - 120))); ctx.rotate(by: CGFloat(r(360)) * .pi / 180)
            (word as NSString).draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()
        }
        UIGraphicsPopContext()
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1)); ctx.setLineWidth(8); ctx.stroke(CGRect(x: 12, y: 12, width: n - 24, height: n - 24))
        return ctx.makeImage()!
    }

    /// Same design, rotated by `degrees` and scaled, with a torn corner and some grey "wall" around it.
    private func variant(of image: CGImage, degrees: CGFloat, scale: CGFloat = 0.8, tear: Bool = false) -> CGImage {
        let n = Int(CGFloat(image.width) * 1.4)
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.translateBy(x: CGFloat(n) / 2, y: CGFloat(n) / 2); ctx.rotate(by: degrees * .pi / 180); ctx.scaleBy(x: scale, y: scale)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        if tear {
            ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
            ctx.fill(CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width) * 0.45, height: CGFloat(image.height) * 0.4))
        }
        return ctx.makeImage()!
    }

    private func inliers(_ a: CGImage, _ b: CGImage) -> Int {
        LocalFeatureMatcher.match(LocalFeatureMatcher.extract(a), LocalFeatureMatcher.extract(b)).inliers
    }

    func testRotatedAndTornCopyStillMatches() {
        let a = sticker(seed: 1)
        XCTAssertGreaterThanOrEqual(inliers(a, variant(of: a, degrees: 35)), 8, "35° rotation")
        XCTAssertGreaterThanOrEqual(inliers(a, variant(of: a, degrees: -70, tear: true)), 8, "-70° + torn corner")
        XCTAssertGreaterThanOrEqual(inliers(a, variant(of: a, degrees: 90, scale: 0.6)), 8, "90° at 60% size")
    }

    func testDifferentDesignsDoNotMatch() {
        let a = sticker(seed: 1), b = sticker(seed: 2), c = sticker(seed: 3)
        XCTAssertLessThan(inliers(a, b), 5)
        XCTAssertLessThan(inliers(a, variant(of: c, degrees: 20)), 5)
    }

    func testMatcherVerdicts() {
        let a = sticker(seed: 7)
        let fa = LocalFeatureMatcher.extract(a).encoded()
        let fb = LocalFeatureMatcher.extract(variant(of: a, degrees: 40)).encoded()
        let fc = LocalFeatureMatcher.extract(sticker(seed: 8)).encoded()
        let sid = UUID()
        let m = SeriesMatcher()
        let v = m.evaluate(newFeatures: fb, newPrint: nil, against: [
            .init(artworkID: UUID(), seriesID: nil, featurePrint: nil, localFeatures: fc),
            .init(artworkID: UUID(), seriesID: sid, featurePrint: nil, localFeatures: fa),
        ])
        guard case .match(_, let seriesID, _) = v else { return XCTFail("expected match, got \(v)") }
        XCTAssertEqual(seriesID, sid)
        XCTAssertEqual(m.evaluate(newFeatures: fb, newPrint: nil, against: [.init(artworkID: UUID(), seriesID: nil, featurePrint: nil, localFeatures: fc)]), .none)
        XCTAssertEqual(m.evaluate(newFeatures: fb, newPrint: nil, against: []), .none)
    }

    /// A design that ended up split across two series (each linked by a different pair) is merged into
    /// one as soon as a new encounter matches both; the user's series name survives, unrelated pieces stay out.
    @MainActor func testAssignMergesSeriesOfTheSameDesign() async throws {
        let container = try GeoGhostSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let base = sticker(seed: 3)
        func piece(_ image: CGImage) -> Artwork {
            let a = Artwork()
            a.localFeatures = LocalFeatureMatcher.extract(image).encoded()
            context.insert(a)
            return a
        }
        let a1 = piece(base), a2 = piece(variant(of: base, degrees: 20))
        let b1 = piece(variant(of: base, degrees: -15)), b2 = piece(variant(of: base, degrees: 40, tear: true))
        let named = ArtSeries(title: "Pink cat"), unnamed = ArtSeries()
        context.insert(named); context.insert(unnamed)
        a1.series = named; a2.series = named; b1.series = unnamed; b2.series = unnamed
        let unrelated = piece(sticker(seed: 99))

        await SeriesAssigner.assign(piece(variant(of: base, degrees: 10)), in: context)

        let series = try context.fetch(FetchDescriptor<ArtSeries>())
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.encounterCount, 5)
        XCTAssertEqual(series.first?.title, "Pink cat")
        XCTAssertNil(unrelated.series)
    }

    func testFeaturesRoundTrip() {
        let f = LocalFeatureMatcher.extract(sticker(seed: 3))
        let d = LocalFeatureMatcher.Features.decode(f.encoded())
        XCTAssertEqual(d?.count, f.count)
        XCTAssertGreaterThan(f.count, 50)
    }
}
