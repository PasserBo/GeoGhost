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
        var closingRadius = 2
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
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let gx = -lum[i - w - 1] + lum[i - w + 1] - 2 * lum[i - 1] + 2 * lum[i + 1] - lum[i + w - 1] + lum[i + w + 1]
                let gy = -lum[i - w - 1] - 2 * lum[i - w] - lum[i - w + 1] + lum[i + w - 1] + 2 * lum[i + w] + lum[i + w + 1]
                edge[i] = (gx * gx + gy * gy).squareRoot() / 4
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

        // Flood fill.
        var mask = [UInt8](repeating: 0, count: w * h)
        var stack = [sy * w + sx]
        mask[sy * w + sx] = 1
        var count = 0
        let tol2 = p.colorTolerance * p.colorTolerance
        while let i = stack.popLast() {
            count += 1
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                guard mask[j] == 0 else { continue }
                if edge[j] > p.edgeThreshold { continue }
                let r = Float(rgba[j * 4]) / 255 - sr, g = Float(rgba[j * 4 + 1]) / 255 - sg, b = Float(rgba[j * 4 + 2]) / 255 - sb
                if r * r + g * g + b * b > tol2 { continue }
                mask[j] = 1
                stack.append(j)
            }
        }
        let total = Double(w * h)
        guard Double(count) / total <= p.maxArea else { return nil }

        // Fill holes: anything not reachable from the image border through non-mask pixels is interior.
        var outside = [UInt8](repeating: 0, count: w * h)
        var q: [Int] = []
        for x in 0..<w { for y in [0, h - 1] { let i = y * w + x; if mask[i] == 0 && outside[i] == 0 { outside[i] = 1; q.append(i) } } }
        for y in 0..<h { for x in [0, w - 1] { let i = y * w + x; if mask[i] == 0 && outside[i] == 0 { outside[i] = 1; q.append(i) } } }
        while let i = q.popLast() {
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                if mask[j] == 0 && outside[j] == 0 { outside[j] = 1; q.append(j) }
            }
        }
        for i in 0..<(w * h) where mask[i] == 0 && outside[i] == 0 { mask[i] = 1 }

        // Morphological closing then opening to knock off speckles and smooth the outline.
        mask = dilate(erode(dilate(mask, w, h, p.closingRadius), w, h, p.closingRadius * 2), w, h, p.closingRadius)

        // Keep only the component containing the seed (closing may have bridged to noise).
        mask = component(of: mask, w, h, containing: sy * w + sx)

        var minX = w, minY = h, maxX = -1, maxY = -1, selected = 0
        for y in 0..<h { for x in 0..<w where mask[y * w + x] != 0 {
            selected += 1
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        let area = Double(selected) / total
        guard maxX >= 0, area >= p.minArea, area <= p.maxArea else { return nil }

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { gray[i] = mask[i] != 0 ? 255 : 0 }
        guard let maskImage = grayImage(gray, w, h) else { return nil }
        let rect = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                          width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        return PointSegmentation(mask: maskImage, boundingRect: rect, area: area)
    }

    // MARK: Morphology helpers (square kernels; fine at 640 px)

    private static func dilate(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var out = m
        for y in 0..<h { for x in 0..<w where m[y * w + x] != 0 {
            for dy in -r...r { let ny = y + dy; guard ny >= 0, ny < h else { continue }
                for dx in -r...r { let nx = x + dx; guard nx >= 0, nx < w else { continue }; out[ny * w + nx] = 1 } }
        } }
        return out
    }

    private static func erode(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var out = m
        for y in 0..<h { for x in 0..<w where m[y * w + x] != 0 {
            var keep = true
            outer: for dy in -r...r { let ny = y + dy
                for dx in -r...r { let nx = x + dx
                    if nx < 0 || ny < 0 || nx >= w || ny >= h || m[ny * w + nx] == 0 { keep = false; break outer } } }
            if !keep { out[y * w + x] = 0 }
        } }
        return out
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
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                if m[j] != 0 && out[j] == 0 { out[j] = 1; stack.append(j) }
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
