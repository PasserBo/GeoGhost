import CoreGraphics
import Foundation
import Vision

/// Suggests an `ArtworkKind` from Vision's built-in image classifier via keyword mapping.
enum KindClassifier {
    struct Suggestion: Sendable { let kind: ArtworkKind; let confidence: Float }

    private static let keywordMap: [(keywords: [String], kind: ArtworkKind)] = [
        (["sticker", "label", "decal", "badge", "emblem", "logo"], .sticker),
        (["graffiti", "spray", "street_art", "aerosol"], .graffiti),
        (["mural", "painting", "fresco", "artwork"], .mural),
        (["poster", "flyer", "billboard", "sign", "signage", "advertisement", "banner"], .poster),
        (["text", "handwriting", "calligraphy", "writing", "lettering", "signature"], .tag),
    ]

    static func suggest(for cutout: CGImage, coversMostOfFrame: Bool) throws -> Suggestion? {
        if coversMostOfFrame { return Suggestion(kind: .mural, confidence: 0.5) }
        let flat = ImageProcessing.flattened(ImageProcessing.downsample(cutout, maxLongEdge: 512))
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: flat, orientation: .up)
        try handler.perform([request])
        let results = (request.results ?? []).filter { $0.confidence > 0.05 }
        var scores: [ArtworkKind: Float] = [:]
        for r in results {
            let id = r.identifier.lowercased()
            for (keywords, kind) in keywordMap where keywords.contains(where: { id.contains($0) }) {
                scores[kind, default: 0] += r.confidence
            }
        }
        guard let (kind, score) = scores.max(by: { $0.value < $1.value }), score >= 0.3 else { return nil }
        return Suggestion(kind: kind, confidence: min(1, score))
    }
}
