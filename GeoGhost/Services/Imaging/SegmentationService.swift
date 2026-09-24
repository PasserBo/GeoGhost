import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Result of running foreground instance segmentation on one image.
/// Holds the Vision handler so cutouts can be generated at full resolution later.
final class SegmentationAnalysis: @unchecked Sendable {
    let image: CGImage
    let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    private let maskWidth: Int
    private let maskHeight: Int
    private let maskLabels: [UInt8]

    init(image: CGImage, observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) {
        self.image = image
        self.observation = observation
        self.handler = handler

        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        maskWidth = CVPixelBufferGetWidth(buffer)
        maskHeight = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<maskHeight {
                for x in 0..<maskWidth { labels[y * maskWidth + x] = ptr[y * rowBytes + x] }
            }
        }
        maskLabels = labels
    }

    var allInstances: IndexSet { observation.allInstances }
    var hasInstances: Bool { !observation.allInstances.isEmpty }

    /// Instance under a normalized point (origin top-left), or nil for background.
    func instance(atNormalized p: CGPoint) -> Int? {
        guard hasInstances else { return nil }
        let x = min(maskWidth - 1, max(0, Int(p.x * CGFloat(maskWidth))))
        let y = min(maskHeight - 1, max(0, Int(p.y * CGFloat(maskHeight))))
        let label = Int(maskLabels[y * maskWidth + x])
        return label == 0 ? nil : label
    }

    /// Normalized pixel area (0…1) of an instance set.
    func area(of instances: IndexSet) -> Double {
        guard maskLabels.count > 0 else { return 0 }
        var count = 0
        for l in maskLabels where l != 0 && instances.contains(Int(l)) { count += 1 }
        return Double(count) / Double(maskLabels.count)
    }

    /// Normalized bounding rect (origin top-left) of an instance set.
    func boundingRect(of instances: IndexSet) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<maskHeight {
            for x in 0..<maskWidth {
                let l = maskLabels[y * maskWidth + x]
                if l != 0 && instances.contains(Int(l)) {
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(maskWidth), y: CGFloat(minY) / CGFloat(maskHeight),
                      width: CGFloat(maxX - minX + 1) / CGFloat(maskWidth), height: CGFloat(maxY - minY + 1) / CGFloat(maskHeight))
    }

    /// Default pick: the instance under the image center, else the largest one.
    func defaultSelection() -> IndexSet {
        guard hasInstances else { return [] }
        if let center = instance(atNormalized: CGPoint(x: 0.5, y: 0.5)) { return [center] }
        var best = 0, bestArea = -1.0
        for i in allInstances {
            let a = area(of: [i])
            if a > bestArea { bestArea = a; best = i }
        }
        return [best]
    }

    /// Soft mask (0…1 float) at the full image resolution for the given instances.
    func scaledMask(for instances: IndexSet) throws -> CVPixelBuffer {
        try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
    }

    /// Transparent cutout of the selected instances, cropped to their extent, at full resolution.
    func cutout(for instances: IndexSet) throws -> CGImage {
        let buffer = try observation.generateMaskedImage(ofInstances: instances, from: handler, croppedToInstancesExtent: true)
        guard let cg = ImageProcessing.cgImage(from: buffer) else { throw SegmentationError.renderFailed }
        return cg
    }

    /// Preview composite: dimmed image with the selected instances at full brightness.
    func previewComposite(selected instances: IndexSet, maxLongEdge: Int = 1280) throws -> CGImage {
        let base = CIImage(cgImage: image)
        let mask = CIImage(cvPixelBuffer: try scaledMask(for: instances))
        let dimmed = base.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.35, kCIInputSaturationKey: 0.4])
        let composed = base.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: dimmed,
            kCIInputMaskImageKey: mask.transformed(by: .init(scaleX: base.extent.width / mask.extent.width, y: base.extent.height / mask.extent.height)),
        ])
        let long = max(base.extent.width, base.extent.height)
        let scale = min(1, CGFloat(maxLongEdge) / long)
        let scaled = composed.transformed(by: .init(scaleX: scale, y: scale))
        guard let out = ImageProcessing.ciContext.createCGImage(scaled, from: scaled.extent.integral) else { throw SegmentationError.renderFailed }
        return out
    }
}

enum SegmentationError: LocalizedError {
    case noResult, renderFailed
    var errorDescription: String? {
        switch self {
        case .noResult: String(localized: "No subject was found in the photo.")
        case .renderFailed: String(localized: "Could not render the cutout.")
        }
    }
}

enum SegmentationService {
    /// Run foreground instance segmentation. Heavy; call off the main thread.
    static func analyze(_ image: CGImage) throws -> SegmentationAnalysis {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw SegmentationError.noResult }
        return SegmentationAnalysis(image: image, observation: observation, handler: handler)
    }
}
