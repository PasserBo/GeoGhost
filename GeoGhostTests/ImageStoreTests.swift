import CoreGraphics
import XCTest
@testable import GeoGhost

final class ImageStoreTests: XCTestCase {
    private func image(_ n: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: n / 2, height: n))
        return ctx.makeImage()!
    }

    func testSaveLoadDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ImageStoreTests-\(UUID().uuidString)")
        let store = ImageStore(root: root)
        let id = UUID()
        let saved = try await store.save(artworkID: id, originalData: Data([0xFF, 0xD8, 0xFF]), originalExtension: "jpg", cutout: image(900))
        XCTAssertEqual(saved.originalID, "original.jpg")

        let thumb = store.loadImage(artworkID: id, imageID: saved.thumbnailID)
        XCTAssertEqual(thumb?.width, ImageStore.thumbnailLongEdge)
        let cutout = store.loadImage(artworkID: id, imageID: saved.cutoutID)
        XCTAssertEqual(cutout?.width, 900)
        XCTAssertEqual(store.loadData(artworkID: id, imageID: saved.originalID), Data([0xFF, 0xD8, 0xFF]))

        let size = await store.totalSize()
        XCTAssertGreaterThan(size, 0)

        await store.delete(artworkID: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: id).path))
        try? FileManager.default.removeItem(at: root)
    }

    func testPNGKeepsAlpha() {
        let png = ImageProcessing.pngData(image(16))!
        let decoded = ImageProcessing.decodeUpright(png)!
        XCTAssertNotEqual(decoded.alphaInfo, .none)
        XCTAssertNotEqual(decoded.alphaInfo, .noneSkipLast)
    }

    func testFileExtensionSniffing() {
        XCTAssertEqual(CaptureFlowModel.fileExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0, count: 12))), "jpg")
        XCTAssertEqual(CaptureFlowModel.fileExtension(for: Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 12))), "png")
        XCTAssertEqual(CaptureFlowModel.fileExtension(for: Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])), "heic")
    }
}
