import CoreGraphics
import XCTest
@testable import GeoGhost

final class LassoSegmenterTests: XCTestCase {
    /// Textured grey wall; white sticker (300×300 at 250…550 × 350…650, CG bottom-left) with black "text" bars and a red logo.
    private func scene() -> CGImage {
        let w = 800, h = 1000
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        srand48(3)
        for _ in 0..<4000 {
            ctx.setFillColor(CGColor(gray: 0.35 + drand48() * 0.2, alpha: 1))
            ctx.fill(CGRect(x: drand48() * 800, y: drand48() * 1000, width: 3, height: 3))
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 250, y: 350, width: 300, height: 300), cornerWidth: 30, cornerHeight: 30, transform: nil)); ctx.fillPath()
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        for i in 0..<4 { ctx.fill(CGRect(x: 280, y: 380 + i * 40, width: 240, height: 14)) }   // lines of text
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 340, y: 550, width: 120, height: 80))
        return ctx.makeImage()!
    }

    /// Loose loop around the sticker (normalized, top-left origin). Sticker spans x 0.3125…0.6875, y 0.35…0.65.
    private var loop: [CGPoint] {
        let cx = 0.5, cy = 0.5, rx = 0.26, ry = 0.22
        return (0..<32).map { i in
            let a = Double(i) / 32 * 2 * .pi
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }

    func testLoopSelectsWholeStickerIncludingText() throws {
        let prep = try XCTUnwrap(PointSegmenter.Prepared(image: scene()))
        let r = try XCTUnwrap(LassoSegmenter.segment(prep, polygon: loop))
        // Whole sticker ≈ 300×300 / 800×1000 = 0.1125
        XCTAssertEqual(r.area, 0.1125, accuracy: 0.02)
        XCTAssertEqual(r.boundingRect.minX, 0.3125, accuracy: 0.02)
        XCTAssertEqual(r.boundingRect.maxX, 0.6875, accuracy: 0.02)
        // The text and logo must be inside (holes filled).
        XCTAssertTrue(r.contains(CGPoint(x: 0.5, y: 0.6)), "text line should be part of the sticker")
        XCTAssertTrue(r.contains(CGPoint(x: 0.5, y: 0.41)), "logo should be part of the sticker")
        // Wall just outside the sticker but inside the loop must not be.
        XCTAssertFalse(r.contains(CGPoint(x: 0.27, y: 0.5)))
    }

    func testLoopOnPlainWallFindsNothing() throws {
        let w = 400, h = 400
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let prep = try XCTUnwrap(PointSegmenter.Prepared(image: ctx.makeImage()!))
        XCTAssertNil(LassoSegmenter.segment(prep, polygon: loop))
    }

    func testRasterizeFillsPolygon() {
        let m = LassoSegmenter.rasterize([CGPoint(x: 2, y: 2), CGPoint(x: 8, y: 2), CGPoint(x: 8, y: 8), CGPoint(x: 2, y: 8)], 10, 10)!
        XCTAssertEqual(m[5 * 10 + 5], 1)
        XCTAssertEqual(m[0], 0)
        XCTAssertEqual(m[9 * 10 + 9], 0)
    }
}
