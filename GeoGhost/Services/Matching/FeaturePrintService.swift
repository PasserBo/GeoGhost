import CoreGraphics
import Foundation
import Vision

/// Computes and compares Vision feature prints (2048-d image embeddings) for design matching.
enum FeaturePrintService {
    /// Serialized `VNFeaturePrintObservation` for a cutout. Alpha is flattened onto neutral grey first.
    static func featurePrint(for cutout: CGImage) throws -> Data {
        let flat = ImageProcessing.flattened(ImageProcessing.downsample(cutout, maxLongEdge: 512))
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: flat, orientation: .up)
        try handler.perform([request])
        guard let obs = request.results?.first else { throw FeaturePrintError.noResult }
        return try NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    static func observation(from data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Distance between two serialized prints; smaller is more similar. Nil if either is unreadable.
    static func distance(_ a: Data, _ b: Data) -> Float? {
        guard let oa = observation(from: a), let ob = observation(from: b) else { return nil }
        var d: Float = 0
        do { try oa.computeDistance(&d, to: ob) } catch { return nil }
        return d
    }
}

enum FeaturePrintError: Error { case noResult }
