import CoreGraphics
import Foundation

/// A mask grown from a single seed point (the piece under the user's finger).
struct PointSegmentation: @unchecked Sendable {
    /// 8-bit grayscale mask at working resolution covering `frame`; 255 = selected.
    let mask: CGImage
    /// Normalized rect (in full-image coordinates, origin top-left) that `mask` covers.
    let frame: CGRect
    /// Normalized bounding rect of the selected pixels, in full-image coordinates.
    let boundingRect: CGRect
    /// Fraction of the full image covered (0…1).
    let area: Double

    /// Whether a normalized full-image point falls on the selected pixels.
    func contains(_ p: CGPoint) -> Bool {
        guard boundingRect.contains(p), let data = mask.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let lx = (p.x - frame.minX) / frame.width, ly = (p.y - frame.minY) / frame.height
        let x = min(mask.width - 1, max(0, Int(lx * CGFloat(mask.width))))
        let y = min(mask.height - 1, max(0, Int(ly * CGFloat(mask.height))))
        return ptr[y * mask.bytesPerRow + x] > 127
    }
}

/// Seed-point segmentation for when Vision's subject model finds nothing (or finds too much).
///
/// Grows a region from the tapped pixel by colour similarity, refuses to cross strong edges,
/// then fills interior holes (a sticker's printed artwork), optionally absorbs the uniform shape
/// wrapping it (the sticker border around the artwork) and smooths the outline.
///
/// `Prepared` caches the expensive per-image work (downsampling, luminance, Sobel edges) so that
/// re-growing with a different tolerance while the finger drags costs only the flood fill.
enum PointSegmenter {
    struct Parameters: Sendable {
        var maxLongEdge = 960
        /// Max RGB distance (0…1, Euclidean over three channels) from the seed colour.
        var colorTolerance: Float = 0.20
        /// Luminance gradient above which a pixel is treated as an edge that stops growth.
        var edgeThreshold: Float = 0.14
        /// Reject results that grabbed most of the frame (the wall, not the sticker).
        var maxArea: Double = 0.65
        var minArea: Double = 0.0005
        /// Regions above this that also touch ≥ 3 frame edges are rejected as background.
        var backgroundArea: Double = 0.2
        var closingRadius = 2
        /// How many enclosing layers to absorb (graphic → sticker face → sticker border).
        var expansionLayers = 2

        static let toleranceRange: ClosedRange<Float> = 0.06...0.45
    }

    /// Per-image preprocessing, reusable across seeds and tolerances.
    final class Prepared: @unchecked Sendable {
        let width: Int
        let height: Int
        /// Normalized rect of the full image this covers (sub-rect when scoped to a viewport).
        let frame: CGRect
        let rgba: [UInt8]
        let edge: [Float]

        /// - Parameters:
        ///   - image: the full upright photo
        ///   - frame: normalized sub-rect to analyse (viewport); `nil` = whole image
        init?(image fullImage: CGImage, frame: CGRect? = nil, maxLongEdge: Int = Parameters().maxLongEdge) {
            var image = fullImage
            var scope = CGRect(x: 0, y: 0, width: 1, height: 1)
            if let frame, frame != scope, let cropped = ImageProcessing.crop(fullImage, normalized: frame) {
                image = cropped
                scope = frame
            }
            let small = ImageProcessing.downsample(image, maxLongEdge: maxLongEdge)
            let w = small.width, h = small.height
            guard w > 2, h > 2 else { return nil }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            ctx.draw(small, in: CGRect(x: 0, y: 0, width: w, height: h))

            var lum = [Float](repeating: 0, count: w * h)
            for i in 0..<(w * h) {
                lum[i] = (0.299 * Float(px[i * 4]) + 0.587 * Float(px[i * 4 + 1]) + 0.114 * Float(px[i * 4 + 2])) / 255
            }
            var e = [Float](repeating: 0, count: w * h)
            lum.withUnsafeBufferPointer { l in
                e.withUnsafeMutableBufferPointer { e in
                    for y in 1..<(h - 1) {
                        for x in 1..<(w - 1) {
                            let i = y * w + x
                            let gx = -l[i - w - 1] + l[i - w + 1] - 2 * l[i - 1] + 2 * l[i + 1] - l[i + w - 1] + l[i + w + 1]
                            let gy = -l[i - w - 1] - 2 * l[i - w] - l[i - w + 1] + l[i + w - 1] + 2 * l[i + w] + l[i + w + 1]
                            e[i] = (gx * gx + gy * gy).squareRoot() / 4
                        }
                    }
                }
            }
            self.width = w; self.height = h; self.frame = scope; self.rgba = px; self.edge = e
        }

        /// Map a normalized full-image point into this buffer's pixel index, or nil if outside the frame.
        func pixelIndex(forNormalized p: CGPoint) -> Int? {
            guard frame.contains(p) || frame.insetBy(dx: -0.001, dy: -0.001).contains(p) else { return nil }
            let lx = (p.x - frame.minX) / frame.width, ly = (p.y - frame.minY) / frame.height
            let x = min(width - 1, max(0, Int(lx * CGFloat(width))))
            let y = min(height - 1, max(0, Int(ly * CGFloat(height))))
            return y * width + x
        }
    }

    /// Convenience: prepare and segment in one go (whole image).
    static func segment(image: CGImage, atNormalized seed: CGPoint, parameters p: Parameters = .init()) -> PointSegmentation? {
        guard let prepared = Prepared(image: image, maxLongEdge: p.maxLongEdge) else { return nil }
        return segment(prepared, atNormalized: seed, parameters: p)
    }

    static func segment(_ prep: Prepared, atNormalized seed: CGPoint, parameters p: Parameters = .init()) -> PointSegmentation? {
        let w = prep.width, h = prep.height
        let rgba = prep.rgba, edge = prep.edge
        guard let seedIndex = prep.pixelIndex(forNormalized: seed) else { return nil }
        let sx = seedIndex % w, sy = seedIndex / w

        // Seed colour: average of a 3×3 patch so a single noisy pixel doesn't steer the fill.
        var sr: Float = 0, sg: Float = 0, sb: Float = 0, n: Float = 0
        for dy in -1...1 { for dx in -1...1 {
            let x = sx + dx, y = sy + dy
            guard x >= 0, y >= 0, x < w, y < h else { continue }
            let i = (y * w + x) * 4
            sr += Float(rgba[i]); sg += Float(rgba[i + 1]); sb += Float(rgba[i + 2]); n += 1
        } }
        sr /= n * 255; sg /= n * 255; sb /= n * 255

        let total = Double(w * h)
        guard var mask = grow(from: [seedIndex], color: (sr, sg, sb), rgba: rgba, edge: edge, w: w, h: h, p: p) else { return nil }
        mask = fillHoles(mask, w, h)

        // Expansion: if the region is wrapped by another uniform, bounded shape (e.g. the sticker's white
        // border around its artwork), absorb it. Stop as soon as the wrapper looks like background.
        for _ in 0..<p.expansionLayers {
            let ring = ringPixels(around: mask, w, h, inner: 2, outer: 6).filter { edge[$0] <= p.edgeThreshold }
            guard ring.count > 8 else { break }
            var rr: Float = 0, rg: Float = 0, rb: Float = 0
            for i in ring { rr += Float(rgba[i * 4]); rg += Float(rgba[i * 4 + 1]); rb += Float(rgba[i * 4 + 2]) }
            let cnt = Float(ring.count) * 255
            let ringColor = (rr / cnt, rg / cnt, rb / cnt)
            let seeds = ring.filter { i in
                let r = Float(rgba[i * 4]) / 255 - ringColor.0, g = Float(rgba[i * 4 + 1]) / 255 - ringColor.1, b = Float(rgba[i * 4 + 2]) / 255 - ringColor.2
                return r * r + g * g + b * b <= p.colorTolerance * p.colorTolerance
            }
            guard Double(seeds.count) >= Double(ring.count) * 0.6 else { break }
            guard let wrapper = grow(from: seeds, color: ringColor, rgba: rgba, edge: edge, w: w, h: h, p: p) else { break }
            let combined = fillHoles(zip(mask, wrapper).map { max($0, $1) }, w, h)
            let stats = bounds(of: combined, w, h)
            guard Double(stats.count) / total <= p.maxArea, stats.edgesTouched(w, h, slack: 1) == 0 else { break }
            mask = combined
        }

        // Closing then opening to knock off speckles and smooth the outline; keep the seed's component.
        mask = dilate(erode(dilate(mask, w, h, p.closingRadius), w, h, p.closingRadius * 2), w, h, p.closingRadius)
        mask = component(of: mask, w, h, containing: seedIndex)

        let stats = bounds(of: mask, w, h)
        let localArea = Double(stats.count) / total
        guard stats.maxX >= 0, localArea >= p.minArea, localArea <= p.maxArea else { return nil }
        // A sizeable region touching three or more frame edges is the wall/sky/pole behind the piece.
        if stats.edgesTouched(w, h, slack: p.closingRadius * 2 + 1) >= 3 && localArea > p.backgroundArea { return nil }

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { gray[i] = mask[i] != 0 ? 255 : 0 }
        guard let maskImage = grayImage(gray, w, h) else { return nil }

        let f = prep.frame
        let localRect = CGRect(x: CGFloat(stats.minX) / CGFloat(w), y: CGFloat(stats.minY) / CGFloat(h),
                               width: CGFloat(stats.maxX - stats.minX + 1) / CGFloat(w), height: CGFloat(stats.maxY - stats.minY + 1) / CGFloat(h))
        let rect = CGRect(x: f.minX + localRect.minX * f.width, y: f.minY + localRect.minY * f.height,
                          width: localRect.width * f.width, height: localRect.height * f.height)
        return PointSegmentation(mask: maskImage, frame: f, boundingRect: rect, area: localArea * Double(f.width * f.height))
    }

    // MARK: Region helpers

    private static func grow(from seeds: [Int], color: (Float, Float, Float), rgba: [UInt8], edge: [Float], w: Int, h: Int, p: Parameters) -> [UInt8]? {
        var mask = [UInt8](repeating: 0, count: w * h)
        var stack: [Int] = []
        for s in seeds where mask[s] == 0 { mask[s] = 1; stack.append(s) }
        let tol2 = p.colorTolerance * p.colorTolerance
        let limit = Int(Double(w * h) * p.maxArea) + 1
        var count = stack.count
        var overflow = false
        rgba.withUnsafeBufferPointer { px in
            edge.withUnsafeBufferPointer { ed in
                mask.withUnsafeMutableBufferPointer { mk in
                    @inline(__always) func visit(_ j: Int) {
                        guard mk[j] == 0, ed[j] <= p.edgeThreshold else { return }
                        let r = Float(px[j * 4]) / 255 - color.0, g = Float(px[j * 4 + 1]) / 255 - color.1, b = Float(px[j * 4 + 2]) / 255 - color.2
                        if r * r + g * g + b * b > tol2 { return }
                        mk[j] = 1
                        count += 1
                        stack.append(j)
                    }
                    while let i = stack.popLast() {
                        if count > limit { overflow = true; return }
                        let x = i % w, y = i / w
                        if x > 0 { visit(i - 1) }
                        if x < w - 1 { visit(i + 1) }
                        if y > 0 { visit(i - w) }
                        if y < h - 1 { visit(i + w) }
                    }
                }
            }
        }
        return overflow ? nil : mask
    }

    private static func fillHoles(_ m: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
        var mask = m
        var outside = [UInt8](repeating: 0, count: w * h)
        var q: [Int] = []
        for x in 0..<w { for y in [0, h - 1] { let i = y * w + x; if mask[i] == 0 && outside[i] == 0 { outside[i] = 1; q.append(i) } } }
        for y in 0..<h { for x in [0, w - 1] { let i = y * w + x; if mask[i] == 0 && outside[i] == 0 { outside[i] = 1; q.append(i) } } }
        mask.withUnsafeBufferPointer { mk in
            outside.withUnsafeMutableBufferPointer { out in
                @inline(__always) func visit(_ j: Int) { if mk[j] == 0 && out[j] == 0 { out[j] = 1; q.append(j) } }
                while let i = q.popLast() {
                    let x = i % w, y = i / w
                    if x > 0 { visit(i - 1) }
                    if x < w - 1 { visit(i + 1) }
                    if y > 0 { visit(i - w) }
                    if y < h - 1 { visit(i + w) }
                }
            }
        }
        for i in 0..<(w * h) where mask[i] == 0 && outside[i] == 0 { mask[i] = 1 }
        return mask
    }

    private static func ringPixels(around m: [UInt8], _ w: Int, _ h: Int, inner: Int, outer: Int) -> [Int] {
        let near = dilate(m, w, h, inner)
        let far = dilate(near, w, h, outer - inner)
        var ring: [Int] = []
        for i in 0..<(w * h) where far[i] != 0 && near[i] == 0 { ring.append(i) }
        return ring
    }

    private struct Bounds {
        var minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int
        func edgesTouched(_ w: Int, _ h: Int, slack: Int) -> Int {
            var n = 0
            if minX <= slack { n += 1 }; if minY <= slack { n += 1 }
            if maxX >= w - 1 - slack { n += 1 }; if maxY >= h - 1 - slack { n += 1 }
            return n
        }
    }

    private static func bounds(of m: [UInt8], _ w: Int, _ h: Int) -> Bounds {
        var b = Bounds(minX: w, minY: h, maxX: -1, maxY: -1, count: 0)
        for y in 0..<h { for x in 0..<w where m[y * w + x] != 0 {
            b.count += 1
            if x < b.minX { b.minX = x }; if x > b.maxX { b.maxX = x }; if y < b.minY { b.minY = y }; if y > b.maxY { b.maxY = y }
        } }
        return b
    }

    private static func dilate(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] { Morphology.dilate(m, w, h, r) }
    private static func erode(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] { Morphology.erode(m, w, h, r) }

    private static func component(of m: [UInt8], _ w: Int, _ h: Int, containing seed: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h)
        var start = seed
        if m[seed] == 0 {
            var best = Int.max
            let sx = seed % w, sy = seed / w
            for y in 0..<h { for x in 0..<w where m[y * w + x] != 0 {
                let d = (x - sx) * (x - sx) + (y - sy) * (y - sy)
                if d < best { best = d; start = y * w + x }
            } }
            if best == Int.max { return out }
        }
        var stack = [start]; out[start] = 1
        m.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                @inline(__always) func visit(_ j: Int) { if src[j] != 0 && dst[j] == 0 { dst[j] = 1; stack.append(j) } }
                while let i = stack.popLast() {
                    let x = i % w, y = i / w
                    if x > 0 { visit(i - 1) }
                    if x < w - 1 { visit(i + 1) }
                    if y > 0 { visit(i - w) }
                    if y < h - 1 { visit(i + w) }
                }
            }
        }
        return out
    }

    private static func grayImage(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
