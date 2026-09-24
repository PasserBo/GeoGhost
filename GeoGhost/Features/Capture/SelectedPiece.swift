import CoreGraphics
import CoreImage
import Foundation

/// One selected thing in the editor, whichever engine produced it.
struct SelectedPiece: Identifiable {
    enum Source {
        case vision(SegmentationAnalysis, instance: Int)
        case region(PointSegmentation)
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

    var isRegion: Bool { if case .region = source { return true }; return false }

    func contains(_ p: CGPoint) -> Bool {
        switch source {
        case .vision(let a, let idx): a.instance(atNormalized: p) == idx
        case .region(let r): r.contains(p)
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
        }
    }
}
