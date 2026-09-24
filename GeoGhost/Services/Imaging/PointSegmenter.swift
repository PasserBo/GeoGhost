import CoreGraphics
import Foundation

/// A mask grown from a single seed point (the piece under the user's finger).
struct PointSegmentation: @unchecked Sendable {
    /// 8-bit grayscale mask at working resolution; 255 = selected.
    let mask: CGImage
    /// Normalized bounding rect (origin top-left).
    let boundingRect: CGRect
    /// Fraction of the image covered (0…1).
    let area: Double

    /// Whether a normalized point falls on the selected pixels.
    func contains(_ p: CGPoint) -> Bool {
        guard boundingRect.contains(p), let data = mask.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let x = min(mask.width - 1, max(0, Int(p.x * CGFloat(mask.width))))
        let y = min(mask.height - 1, max(0, Int(p.y * CGFloat(mask.height))))
        return ptr[y * mask.bytesPerRow + x] > 127
    }
}

/// Seed-point segmentation for when Vision's subject model finds nothing.
///
/// Grows a region from the tapped pixel by colour similarity, refuses to cross strong edges,
/// then fills interior holes (a sticker's printed artwork) and smooths the outline. Runs in
/// ~60–150 ms on a 960 px working copy, so it feels immediate after a long-press.
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
    }

    static func segment(image: CGImage, atNormalized seed: CGPoint, parameters p: Parameters = .init()) -> PointSegmentation? {
        let small = ImageProcessing.downsample(image, maxLongEdge: p.maxLongEdge)
        let w = small.width, h = small.height
        guard w > 2, h > 2 else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.draw(small, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Luminance + Sobel gradient magnitude.
        var lum = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            lum[i] = (0.299 * Float(rgba[i * 4]) + 0.587 * Float(rgba[i * 4 + 1]) + 0.114 * Float(rgba[i * 4 + 2])) / 255
        }
        var edge = [Float](repeating: 0, count: w * h)
        lum.withUnsafeBufferPointer { l in
            edge.withUnsafeMutableBufferPointer { e in
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

        let sx = min(w - 1, max(0, Int(seed.x * CGFloat(w))))
        let sy = min(h - 1, max(0, Int(seed.y * CGFloat(h))))
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
        // Flood fill from the seed, then fill holes so a sticker's printed graphic comes along.
        guard var mask = grow(from: [sy * w + sx], color: (sr, sg, sb), rgba: rgba, edge: edge, w: w, h: h, p: p),
              Double(mask.reduce(0) { $0 + Int($1) }) / total <= p.maxArea else { return nil }
        mask = fillHoles(mask, w, h)

        // Expansion: if the region is wrapped by another uniform, bounded shape (e.g. the sticker's white
        // border around its artwork), absorb it. Stop as soon as the wrapper looks like background.
        for _ in 0..<p.expansionLayers {
            // Skip the 2 px anti-aliased boundary, then sample a 4 px band; ignore edge pixels inside it.
            let ring = ringPixels(around: mask, w, h, inner: 2, outer: 6).filter { edge[$0] <= p.edgeThreshold }
            guard ring.count > 8 else { break }
            var rr: Float = 0, rg: Float = 0, rb: Float = 0
            for i in ring { rr += Float(rgba[i * 4]); rg += Float(rgba[i * 4 + 1]); rb += Float(rgba[i * 4 + 2]) }
            let n = Float(ring.count) * 255
            let ringColor = (rr / n, rg / n, rb / n)
            // Only seed from ring pixels that actually match the ring's dominant colour.
            let seeds = ring.filter { i in
                let r = Float(rgba[i * 4]) / 255 - ringColor.0, g = Float(rgba[i * 4 + 1]) / 255 - ringColor.1, b = Float(rgba[i * 4 + 2]) / 255 - ringColor.2
                return r * r + g * g + b * b <= p.colorTolerance * p.colorTolerance
            }
            // The wrapper must be dominated by one colour, otherwise it's just background texture.
            guard Double(seeds.count) >= Double(ring.count) * 0.6 else { break }
            guard let wrapper = grow(from: seeds, color: ringColor, rgba: rgba, edge: edge, w: w, h: h, p: p) else { break }
            let combined = fillHoles(zip(mask, wrapper).map { max($0, $1) }, w, h)
            let stats = bounds(of: combined, w, h)
            let area = Double(stats.count) / total
            guard area <= p.maxArea, stats.edgesTouched(w, h, slack: 1) == 0 else { break }
            mask = combined
        }

        // Morphological closing then opening to knock off speckles and smooth the outline.
        mask = dilate(erode(dilate(mask, w, h, p.closingRadius), w, h, p.closingRadius * 2), w, h, p.closingRadius)

        // Keep only the component containing the seed (closing may have bridged to noise).
        mask = component(of: mask, w, h, containing: sy * w + sx)

        let stats = bounds(of: mask, w, h)
        let area = Double(stats.count) / total
        guard stats.maxX >= 0, area >= p.minArea, area <= p.maxArea else { return nil }
        // A sizeable region touching three or more frame edges is the wall/sky/pole behind the piece, not the piece.
        // Morphology pulls the outline in by up to 2·radius px, so allow that much slack at the border.
        if stats.edgesTouched(w, h, slack: p.closingRadius * 2 + 1) >= 3 && area > p.backgroundArea { return nil }
        let (minX, minY, maxX, maxY) = (stats.minX, stats.minY, stats.maxX, stats.maxY)

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { gray[i] = mask[i] != 0 ? 255 : 0 }
        guard let maskImage = grayImage(gray, w, h) else { return nil }
        let rect = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                          width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        return PointSegmentation(mask: maskImage, boundingRect: rect, area: area)
    }

    // MARK: Region helpers

    /// 4-connected flood fill from `seeds`, bounded by colour distance to `color` and by strong edges.
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

    /// Anything not reachable from the image border through non-mask pixels is interior → becomes mask.
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

    /// Band of pixels between `inner` and `outer` px outside the mask.
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

    // MARK: Morphology helpers (square kernels; fine at 960 px)

    /// Square-kernel dilation as two separable 1-D passes: O(w·h·r) instead of O(w·h·r²).
    private static func dilate(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var tmp = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where m[row + x] != 0 {
                for nx in max(0, x - r)...min(w - 1, x + r) { tmp[row + nx] = 1 }
            }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w {
            for y in 0..<h where tmp[y * w + x] != 0 {
                for ny in max(0, y - r)...min(h - 1, y + r) { out[ny * w + x] = 1 }
            }
        }
        return out
    }

    /// Erosion = complement of dilating the complement (pixels outside the frame count as background).
    private static func erode(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var inv = m.map { $0 == 0 ? UInt8(1) : UInt8(0) }
        // Treat the frame border as background so shapes touching it erode there too.
        for x in 0..<w { inv[x] = 1; inv[(h - 1) * w + x] = 1 }
        for y in 0..<h { inv[y * w] = 1; inv[y * w + w - 1] = 1 }
        let grown = dilate(inv, w, h, r)
        return grown.map { $0 == 0 ? UInt8(1) : UInt8(0) }
    }

    private static func component(of m: [UInt8], _ w: Int, _ h: Int, containing seed: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h)
        // If closing removed the seed pixel itself, fall back to the nearest mask pixel.
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
