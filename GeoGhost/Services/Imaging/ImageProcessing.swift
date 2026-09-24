import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Stateless image helpers. Everything here is safe to call from any thread.
enum ImageProcessing {
    static let ciContext = CIContext(options: [.cacheIntermediates: false, .name: "GeoGhost"])

    /// Decode image data into an upright CGImage (EXIF orientation applied).
    static func decodeUpright(_ data: Data, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Scale so the long edge equals `maxLongEdge` (never upscales).
    static func downsample(_ image: CGImage, maxLongEdge: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > maxLongEdge else { return image }
        let scale = CGFloat(maxLongEdge) / CGFloat(long)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let ci = CIImage(cgImage: image).transformed(by: .init(scaleX: scale, y: scale))
        return ciContext.createCGImage(ci, from: CGRect(origin: .zero, size: size).integral) ?? image
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Crop by a normalized rect (origin top-left, 0…1).
    static func crop(_ image: CGImage, normalized rect: CGRect) -> CGImage? {
        let px = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                        width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
        return image.cropping(to: px)
    }

    /// Average color over opaque pixels of a small version of the image, as `#RRGGBB`.
    static func dominantColorHex(_ image: CGImage) -> String? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard px[3] > 0 else { return nil }
        // Un-premultiply so a mostly-transparent cutout still yields its real color.
        let a = CGFloat(px[3]) / 255
        let r = min(255, Int(CGFloat(px[0]) / a)), g = min(255, Int(CGFloat(px[1]) / a)), b = min(255, Int(CGFloat(px[2]) / a))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Composite a transparent image over a solid color so ML models don't read alpha as black.
    static func flattened(_ image: CGImage, on color: CIColor = CIColor(red: 0.5, green: 0.5, blue: 0.5)) -> CGImage {
        let ci = CIImage(cgImage: image)
        let bg = CIImage(color: color).cropped(to: ci.extent)
        let out = ci.composited(over: bg)
        return ciContext.createCGImage(out, from: ci.extent) ?? image
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
