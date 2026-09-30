import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Result of running foreground instance segmentation on one image.
/// Holds the Vision handler so cutouts can be generated at full resolution later.
final class SegmentationAnalysis: @unchecked Sendable {
    let image: CGImage
    /// Normalized rect of the full photo this analysis covers (a viewport crop when zoomed in).
    let frame: CGRect
    let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    private let maskWidth: Int
    private let maskHeight: Int
    private let maskLabels: [UInt8]

    init(image: CGImage, frame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) {
        self.image = image
        self.frame = frame
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

    /// Instance under a normalized full-photo point (origin top-left), or nil for background / outside frame.
    func instance(atNormalized full: CGPoint) -> Int? {
        guard hasInstances, frame.contains(full) else { return nil }
        let p = CGPoint(x: (full.x - frame.minX) / frame.width, y: (full.y - frame.minY) / frame.height)
        let x = min(maskWidth - 1, max(0, Int(p.x * CGFloat(maskWidth))))
        let y = min(maskHeight - 1, max(0, Int(p.y * CGFloat(maskHeight))))
        let label = Int(maskLabels[y * maskWidth + x])
        return label == 0 ? nil : label
    }

    /// Area of an instance set as a fraction of the full photo.
    func area(of instances: IndexSet) -> Double {
        guard maskLabels.count > 0 else { return 0 }
        var count = 0
        for l in maskLabels where l != 0 && instances.contains(Int(l)) { count += 1 }
        return Double(count) / Double(maskLabels.count) * Double(frame.width * frame.height)
    }

    /// Bounding rect of an instance set in normalized full-photo coordinates (origin top-left).
    func boundingRect(of instances: IndexSet) -> CGRect? {
        guard let local = localBoundingRect(of: instances) else { return nil }
        return CGRect(x: frame.minX + local.minX * frame.width, y: frame.minY + local.minY * frame.height,
                      width: local.width * frame.width, height: local.height * frame.height)
    }

    private func localBoundingRect(of instances: IndexSet) -> CGRect? {
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

    /// For each instance, the fraction of its pixels that fall inside a polygon (normalized full-photo coords).
    func coverage(insidePolygon polygon: [CGPoint]) -> [Int: Double] {
        // Polygon → mask pixel space.
        let pts = polygon.map { CGPoint(x: ($0.x - frame.minX) / frame.width * CGFloat(maskWidth), y: ($0.y - frame.minY) / frame.height * CGFloat(maskHeight)) }
        guard let inside = LassoSegmenter.rasterize(pts, maskWidth, maskHeight) else { return [:] }
        var total: [Int: Int] = [:], hit: [Int: Int] = [:]
        for i in 0..<maskLabels.count {
            let l = Int(maskLabels[i]); guard l != 0 else { continue }
            total[l, default: 0] += 1
            if inside[i] != 0 { hit[l, default: 0] += 1 }
        }
        var out: [Int: Double] = [:]
        for (l, t) in total { out[l] = Double(hit[l] ?? 0) / Double(t) }
        return out
    }

    /// Default pick: the instance under the frame center, else the largest one.
    func defaultSelection() -> IndexSet {
        guard hasInstances else { return [] }
        if let center = instance(atNormalized: CGPoint(x: frame.midX, y: frame.midY)) { return [center] }
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
    /// - Parameter frame: normalized sub-rect of the photo to analyse (the zoomed viewport); nil = whole photo.
    static func analyze(_ fullImage: CGImage, frame: CGRect? = nil) throws -> SegmentationAnalysis {
        var image = fullImage
        var f = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let frame, frame != f, let cropped = ImageProcessing.crop(fullImage, normalized: frame) {
            image = cropped
            f = frame
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw SegmentationError.noResult }
        return SegmentationAnalysis(image: image, frame: f, observation: observation, handler: handler)
    }
}
