import CoreGraphics
import XCTest
@testable import GeoGhost

final class PointSegmenterTests: XCTestCase {
    /// Grey noisy wall with a white rounded sticker carrying a red graphic in the middle.
    private func scene() -> CGImage {
        let w = 800, h = 1000
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        srand48(7)
        for _ in 0..<3000 {
            ctx.setFillColor(CGColor(gray: 0.35 + drand48() * 0.2, alpha: 1))
            ctx.fill(CGRect(x: drand48() * 800, y: drand48() * 1000, width: 3, height: 3))
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 250, y: 350, width: 300, height: 300), cornerWidth: 40, cornerHeight: 40, transform: nil)); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 320, y: 420, width: 160, height: 160))
        return ctx.makeImage()!
    }

    func testSeedOnStickerBorderGrabsWholeSticker() {
        // CoreGraphics origin is bottom-left; the sticker spans x 250–550, y 350–650 → normalized centre (0.5, 0.5).
        let r = PointSegmenter.segment(image: scene(), atNormalized: CGPoint(x: 0.35, y: 0.5))
        XCTAssertNotNil(r)
        guard let r else { return }
        // Whole sticker incl. the red graphic (hole filled): ~300×300 of 800×1000 = 0.1125
        XCTAssertEqual(r.area, 0.1125, accuracy: 0.02)
        XCTAssertEqual(r.boundingRect.minX, 250.0 / 800, accuracy: 0.02)
        XCTAssertEqual(r.boundingRect.width, 300.0 / 800, accuracy: 0.03)
        XCTAssertEqual(r.boundingRect.height, 300.0 / 1000, accuracy: 0.03)
    }

    func testSeedOnGraphicGrabsJustTheGraphic() {
        let r = PointSegmenter.segment(image: scene(), atNormalized: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNotNil(r)
        guard let r else { return }
        XCTAssertEqual(r.area, Double.pi * 80 * 80 / 800_000, accuracy: 0.01)
    }

    func testSeedOnWallIsRejectedAsTooLarge() {
        XCTAssertNil(PointSegmenter.segment(image: scene(), atNormalized: CGPoint(x: 0.1, y: 0.1)))
    }
}
