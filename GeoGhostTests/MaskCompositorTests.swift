import CoreGraphics
import CoreImage
import XCTest
@testable import GeoGhost

final class MaskCompositorTests: XCTestCase {
    private func squareMask(_ n: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: n * n)
        for y in (n / 4)..<(3 * n / 4) { for x in (n / 4)..<(3 * n / 4) { bytes[y * n + x] = 255 } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func alpha(_ img: CGImage, x: Int, y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return px[3]
    }

    func testPlacePutsMaskIntoFullFrame() {
        let size = CGSize(width: 400, height: 400)
        // Mask covering the bottom-right quarter of the photo.
        let placed = MaskCompositor.place(CIImage(cgImage: squareMask(64)), frame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), in: size)
        XCTAssertEqual(placed.extent, CGRect(origin: .zero, size: size))
        let cg = ImageProcessing.ciContext.createCGImage(placed, from: placed.extent)!
        // Square is the middle half of the quarter → photo coords x 250…350, y 250…350 (top-left origin).
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -300, y: -(400 - 1 - 300), width: 400, height: 400)); XCTAssertGreaterThan(px[0], 200, "inside square should be white")
        ctx.draw(cg, in: CGRect(x: -100, y: -(400 - 1 - 100), width: 400, height: 400)); XCTAssertLessThan(px[0], 30, "outside should be black")
    }

    func testOutlineIsARingAroundTheEdge() {
        let size = CGSize(width: 256, height: 256)
        let mask = MaskCompositor.place(CIImage(cgImage: squareMask(256)), frame: CGRect(x: 0, y: 0, width: 1, height: 1), in: size)
        let outline = MaskCompositor.outline(mask: mask, imageSize: size, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), thickness: 3)!
        XCTAssertEqual(outline.width, 256)
        XCTAssertGreaterThan(alpha(outline, x: 64, y: 128), 128, "on the edge → opaque")
        XCTAssertLessThan(alpha(outline, x: 128, y: 128), 20, "centre → transparent")
        XCTAssertLessThan(alpha(outline, x: 10, y: 10), 20, "far outside → transparent")
    }
}
