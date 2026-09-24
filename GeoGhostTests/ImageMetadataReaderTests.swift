import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GeoGhost

final class ImageMetadataReaderTests: XCTestCase {
    /// Build a tiny JPEG with the given EXIF/GPS so tests don't depend on fixture files.
    private func makeJPEG(gps: [CFString: Any]?, exif: [CFString: Any]?, tiff: [CFString: Any]? = nil) -> Data {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let gps { props[kCGImagePropertyGPSDictionary] = gps }
        if let exif { props[kCGImagePropertyExifDictionary] = exif }
        if let tiff { props[kCGImagePropertyTIFFDictionary] = tiff }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testReadsGPSWithHemispheres() {
        let data = makeJPEG(gps: [kCGImagePropertyGPSLatitude: 35.6595, kCGImagePropertyGPSLatitudeRef: "N",
                                  kCGImagePropertyGPSLongitude: 139.7005, kCGImagePropertyGPSLongitudeRef: "E",
                                  kCGImagePropertyGPSImgDirection: 270.0], exif: nil)
        let m = ImageMetadataReader.read(data)
        XCTAssertEqual(m.latitude ?? 0, 35.6595, accuracy: 0.0001)
        XCTAssertEqual(m.longitude ?? 0, 139.7005, accuracy: 0.0001)
        XCTAssertEqual(m.heading, 270)
        XCTAssertEqual(m.locationSource, .exif)
        XCTAssertNotNil(m.coordinate)
    }

    func testSouthWestAreNegative() {
        let data = makeJPEG(gps: [kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
                                  kCGImagePropertyGPSLongitude: 70.6693, kCGImagePropertyGPSLongitudeRef: "W"], exif: nil)
        let m = ImageMetadataReader.read(data)
        XCTAssertEqual(m.latitude ?? 0, -33.8688, accuracy: 0.0001)
        XCTAssertEqual(m.longitude ?? 0, -70.6693, accuracy: 0.0001)
    }

    func testNoGPSMeansNoLocation() {
        let m = ImageMetadataReader.read(makeJPEG(gps: nil, exif: nil))
        XCTAssertNil(m.coordinate)
        XCTAssertEqual(m.locationSource, .none)
        XCTAssertEqual(m.pixelWidth, 8)
    }

    func testParsesExifDateWithOffset() {
        let d = ImageMetadataReader.parseExifDate("2026:09:24 14:32:07", offset: "+09:00")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.hour, .minute, .day], from: d)
        XCTAssertEqual(c.day, 24); XCTAssertEqual(c.hour, 5); XCTAssertEqual(c.minute, 32)
    }

    func testReadsDateAndDeviceFromEmbeddedMetadata() {
        let data = makeJPEG(gps: nil, exif: [kCGImagePropertyExifDateTimeOriginal: "2025:01:02 03:04:05", kCGImagePropertyExifLensModel: "iPhone 16 Pro back camera"],
                            tiff: [kCGImagePropertyTIFFModel: "iPhone 16 Pro"])
        let m = ImageMetadataReader.read(data)
        XCTAssertNotNil(m.capturedAt)
        XCTAssertEqual(m.deviceModel, "iPhone 16 Pro")
        XCTAssertEqual(m.lensModel, "iPhone 16 Pro back camera")
    }

    func testGPSDictionaryRoundTrips() {
        let dict = ImageMetadataReader.gpsDictionary(latitude: -12.5, longitude: 130.25, altitude: -3, accuracy: 8, heading: 45, date: Date())
        let data = makeJPEG(gps: dict as [CFString: Any]? ?? nil, exif: nil)
        // gpsDictionary returns String keys; convert for the writer.
        let cf = Dictionary(uniqueKeysWithValues: dict.map { (($0.key as CFString), $0.value) })
        let m = ImageMetadataReader.read(makeJPEG(gps: cf, exif: nil))
        _ = data
        XCTAssertEqual(m.latitude ?? 0, -12.5, accuracy: 0.0001)
        XCTAssertEqual(m.longitude ?? 0, 130.25, accuracy: 0.0001)
        XCTAssertEqual(m.altitude ?? 0, -3, accuracy: 0.001)
        XCTAssertEqual(m.horizontalAccuracy, 8)
        XCTAssertEqual(m.heading, 45)
    }
}
