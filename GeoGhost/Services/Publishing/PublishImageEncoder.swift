import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The two images uploaded for a public post (design.md §8): the cutout only, never the original
/// photo, as HEIC with transparency and no metadata at all (no location, time or device).
/// Measured on 74 real cutouts: about 80 KB for the full image and 21 KB for the thumbnail.
enum PublishImageEncoder {
    static let fullLongEdge = 1024
    static let thumbLongEdge = 400
    static let quality = 0.7
    /// The Worker refuses anything larger (design.md §7).
    static let fullMaxBytes = 1_500_000
    static let thumbMaxBytes = 300_000

    struct Output: Sendable {
        let full: Data
        let thumb: Data
        let fullWidth: Int
        let fullHeight: Int
    }

    enum EncodeError: Error {
        case encodingFailed
        case tooLarge
    }

    static func encode(_ cutout: CGImage) throws -> Output {
        let full = ImageProcessing.downsample(cutout, maxLongEdge: fullLongEdge)
        let thumb = ImageProcessing.downsample(cutout, maxLongEdge: thumbLongEdge)
        guard let fullData = heic(full), let thumbData = heic(thumb) else { throw EncodeError.encodingFailed }
        guard fullData.count <= fullMaxBytes, thumbData.count <= thumbMaxBytes else { throw EncodeError.tooLarge }
        return Output(full: fullData, thumb: thumbData, fullWidth: full.width, fullHeight: full.height)
    }

    /// Only the pixels go in: no properties dictionary means no EXIF, GPS or TIFF blocks.
    static func heic(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
