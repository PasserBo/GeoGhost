import CoreGraphics
import CoreImage
import Foundation

/// One selected thing in the editor, whichever engine produced it.
struct SelectedPiece: Identifiable {
    enum Source {
        case vision(SegmentationAnalysis, instance: Int)
        case region(PointSegmentation)
        /// An artwork's existing cutout (alpha channel = mask), placed at its saved rect. Used when editing.
        case stored(alpha: CGImage, rect: CGRect)
    }

    let id: UUID
    let source: Source
    /// Normalized bounding rect in full-photo coordinates (origin top-left).
    let rect: CGRect
    /// Fraction of the full photo covered.
    let area: Double

    init(id: UUID = UUID(), vision analysis: SegmentationAnalysis, instance: Int) {
        self.id = id
        source = .vision(analysis, instance: instance)
        rect = analysis.boundingRect(of: [instance]) ?? analysis.frame
        area = analysis.area(of: [instance])
    }

    init(id: UUID = UUID(), region: PointSegmentation) {
        self.id = id
        source = .region(region)
        rect = region.boundingRect
        area = region.area
    }

    init(id: UUID = UUID(), storedCutout: CGImage, rect: CGRect, imageSize: CGSize) {
        self.id = id
        source = .stored(alpha: storedCutout, rect: rect)
        self.rect = rect
        area = Double(rect.width * rect.height) * 0.8
    }

    var isRegion: Bool { if case .region = source { return true }; return false }
    var isStored: Bool { if case .stored = source { return true }; return false }

    func contains(_ p: CGPoint) -> Bool {
        switch source {
        case .vision(let a, let idx): return a.instance(atNormalized: p) == idx
        case .region(let r): return r.contains(p)
        case .stored(let alpha, let r):
            guard r.contains(p), let data = alpha.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
            let x = min(alpha.width - 1, max(0, Int((p.x - r.minX) / r.width * CGFloat(alpha.width))))
            let y = min(alpha.height - 1, max(0, Int((p.y - r.minY) / r.height * CGFloat(alpha.height))))
            let bpp = alpha.bitsPerPixel / 8
            let alphaOffset = (alpha.alphaInfo == .premultipliedFirst || alpha.alphaInfo == .first) ? 0 : bpp - 1
            return ptr[y * alpha.bytesPerRow + x * bpp + alphaOffset] > 64
        }
    }

    /// Mask in full-photo pixel space (Core Image coordinates), ready to union with other pieces.
    func mask(fullSize: CGSize) -> CIImage? {
        switch source {
        case .vision(let a, let idx):
            guard let buffer = try? a.scaledMask(for: [idx]) else { return nil }
            return MaskCompositor.place(CIImage(cvPixelBuffer: buffer), frame: a.frame, in: fullSize)
        case .region(let r):
            let raw = CIImage(cgImage: r.mask)
            let placed = MaskCompositor.place(raw, frame: r.frame, in: fullSize)
            // Hard low-res mask → blur to interpolate, then steepen so edges stay crisp.
            return MaskCompositor.sharpened(MaskCompositor.feathered(placed, radius: 2.5))
        case .stored(let alpha, let r):
            // Alpha channel of the saved cutout becomes the mask.
            let a = CIImage(cgImage: alpha).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            return MaskCompositor.place(a, frame: r, in: fullSize)
        }
    }
}
