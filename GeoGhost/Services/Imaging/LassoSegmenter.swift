import CoreGraphics
import Foundation

/// Segmentation from a rough loop drawn around the piece.
///
/// The loop gives a strong prior the point-based grower never has: *everything just outside the
/// loop is background*. We build a colour model of that ring, then keep every pixel inside the
/// loop that doesn't look like background — so a sticker's text, artwork and border all come
/// along regardless of how many colours it has, as long as it differs from the wall.
enum LassoSegmenter {
    struct Parameters: Sendable {
        /// Ring width outside the loop used to sample background, as a fraction of the loop's larger side.
        var ringFraction: CGFloat = 0.08
        var ringMinPx = 6
        var ringMaxPx = 40
        var backgroundClusters = 5
        var foregroundClusters = 4
        /// A pixel closer than this (RGB, 0…1) to a background cluster is background.
        var backgroundTolerance: Float = 0.10
        /// Drop islands smaller than this fraction of the loop area (unless they are all there is).
        var minIslandFraction: Double = 0.01
        /// Give up if the foreground is less than this fraction of the loop.
        var minCoverage: Double = 0.04
    }

    /// - Parameters:
    ///   - prep: preprocessed photo (or viewport)
    ///   - polygon: loop in normalized full-photo coordinates (origin top-left), ≥ 3 points
    static func segment(_ prep: PointSegmenter.Prepared, polygon: [CGPoint], parameters p: Parameters = .init()) -> PointSegmentation? {
        let w = prep.width, h = prep.height
        guard polygon.count >= 3 else { return nil }
        let f = prep.frame
        // Loop in prep pixel space.
        let pts = polygon.map { CGPoint(x: ($0.x - f.minX) / f.width * CGFloat(w), y: ($0.y - f.minY) / f.height * CGFloat(h)) }
        guard let inside = rasterize(pts, w, h) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1, insideCount = 0
        for y in 0..<h { for x in 0..<w where inside[y * w + x] != 0 {
            insideCount += 1
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        guard insideCount > 64, maxX >= 0 else { return nil }

        // Background ring just outside the loop.
        let side = max(maxX - minX, maxY - minY)
        let ringPx = min(p.ringMaxPx, max(p.ringMinPx, Int(CGFloat(side) * p.ringFraction)))
        let grown = Morphology.dilate(inside, w, h, ringPx)
        var ring: [Int] = []
        for i in 0..<(w * h) where grown[i] != 0 && inside[i] == 0 { ring.append(i) }
        guard ring.count > 32 else { return nil }
        let rgba = prep.rgba
        let bgCenters = kMeans(sample(ring, limit: 4000).map { color(rgba, $0) }, k: p.backgroundClusters)

        // First pass: anything inside that isn't background-coloured.
        var interior: [Int] = []
        interior.reserveCapacity(insideCount)
        for i in 0..<(w * h) where inside[i] != 0 { interior.append(i) }
        var fg = [UInt8](repeating: 0, count: w * h)
        var fgSamples: [SIMD3<Float>] = []
        let tol2 = p.backgroundTolerance * p.backgroundTolerance
        for i in interior {
            let c = color(rgba, i)
            if nearestDistance2(c, bgCenters) > tol2 { fg[i] = 1; if fgSamples.count < 6000 { fgSamples.append(c) } }
        }
        // Second pass: compete foreground vs background colour models (handles walls with texture).
        if fgSamples.count >= 32 {
            let fgCenters = kMeans(fgSamples, k: p.foregroundClusters)
            for i in interior {
                let c = color(rgba, i)
                let dBg = nearestDistance2(c, bgCenters), dFg = nearestDistance2(c, fgCenters)
                fg[i] = (dFg < dBg && dBg > tol2 * 0.25) ? 1 : 0
            }
        }

        // Clean up: open to kill specks, fill holes inside the loop (text, printed artwork), close.
        var mask = Morphology.dilate(Morphology.erode(fg, w, h, 1), w, h, 1)
        mask = fillHoles(mask, within: inside, w, h)
        mask = Morphology.dilate(Morphology.erode(Morphology.dilate(mask, w, h, 2), w, h, 4), w, h, 2)
        mask = dropSmallIslands(mask, w, h, minCount: Int(Double(insideCount) * p.minIslandFraction))

        var count = 0
        var bMinX = w, bMinY = h, bMaxX = -1, bMaxY = -1
        for y in 0..<h { for x in 0..<w where mask[y * w + x] != 0 {
            count += 1
            if x < bMinX { bMinX = x }; if x > bMaxX { bMaxX = x }; if y < bMinY { bMinY = y }; if y > bMaxY { bMaxY = y }
        } }
        guard bMaxX >= 0, Double(count) / Double(insideCount) >= p.minCoverage else { return nil }

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { gray[i] = mask[i] != 0 ? 255 : 0 }
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let maskImage = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let localRect = CGRect(x: CGFloat(bMinX) / CGFloat(w), y: CGFloat(bMinY) / CGFloat(h),
                               width: CGFloat(bMaxX - bMinX + 1) / CGFloat(w), height: CGFloat(bMaxY - bMinY + 1) / CGFloat(h))
        let rect = CGRect(x: f.minX + localRect.minX * f.width, y: f.minY + localRect.minY * f.height,
                          width: localRect.width * f.width, height: localRect.height * f.height)
        return PointSegmentation(mask: maskImage, frame: f, boundingRect: rect, area: Double(count) / Double(w * h) * Double(f.width * f.height))
    }

    // MARK: Helpers

    /// Fill a closed polygon into an 8-bit mask (top-left origin).
    static func rasterize(_ pts: [CGPoint], _ w: Int, _ h: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // CGContext bitmaps are bottom-up; flip so row 0 is the top.
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.beginPath()
            ctx.move(to: pts[0])
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.fillPath(using: .winding)
            return true
        }
        guard ok else { return nil }
        for i in 0..<(w * h) { bytes[i] = bytes[i] > 127 ? 1 : 0 }
        return bytes
    }

    @inline(__always) private static func color(_ rgba: [UInt8], _ i: Int) -> SIMD3<Float> {
        SIMD3(Float(rgba[i * 4]) / 255, Float(rgba[i * 4 + 1]) / 255, Float(rgba[i * 4 + 2]) / 255)
    }

    private static func nearestDistance2(_ c: SIMD3<Float>, _ centers: [SIMD3<Float>]) -> Float {
        var best = Float.greatestFiniteMagnitude
        for k in centers { let d = c - k; let d2 = (d * d).sum(); if d2 < best { best = d2 } }
        return best
    }

    private static func sample(_ idx: [Int], limit: Int) -> [Int] {
        guard idx.count > limit else { return idx }
        let step = idx.count / limit
        return stride(from: 0, to: idx.count, by: step).map { idx[$0] }
    }

    /// Plain k-means in RGB; deterministic seeding along the sample order. Small inputs, few iterations.
    static func kMeans(_ samples: [SIMD3<Float>], k: Int, iterations: Int = 8) -> [SIMD3<Float>] {
        guard !samples.isEmpty else { return [] }
        let k = min(k, samples.count)
        var centers = (0..<k).map { samples[$0 * samples.count / k] }
        var assign = [Int](repeating: 0, count: samples.count)
        for _ in 0..<iterations {
            for (i, s) in samples.enumerated() {
                var best = 0, bd = Float.greatestFiniteMagnitude
                for (j, c) in centers.enumerated() { let d = s - c; let d2 = (d * d).sum(); if d2 < bd { bd = d2; best = j } }
                assign[i] = best
            }
            var sums = [SIMD3<Float>](repeating: .zero, count: k), counts = [Int](repeating: 0, count: k)
            for (i, s) in samples.enumerated() { sums[assign[i]] += s; counts[assign[i]] += 1 }
            for j in 0..<k where counts[j] > 0 { centers[j] = sums[j] / Float(counts[j]) }
        }
        return centers
    }

    /// Non-foreground pixels inside the loop that can't reach the loop boundary are holes → fill them.
    private static func fillHoles(_ m: [UInt8], within inside: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
        var mask = m
        var reach = [UInt8](repeating: 0, count: w * h)
        var q: [Int] = []
        // Seeds: non-mask pixels inside the loop that touch the loop boundary (have a neighbour outside).
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            guard inside[i] != 0, mask[i] == 0 else { continue }
            let edgeAdjacent = x == 0 || y == 0 || x == w - 1 || y == h - 1 || inside[i - 1] == 0 || inside[i + 1] == 0 || inside[i - w] == 0 || inside[i + w] == 0
            if edgeAdjacent { reach[i] = 1; q.append(i) }
        } }
        mask.withUnsafeBufferPointer { mk in
            inside.withUnsafeBufferPointer { ins in
                reach.withUnsafeMutableBufferPointer { r in
                    @inline(__always) func visit(_ j: Int) { if ins[j] != 0 && mk[j] == 0 && r[j] == 0 { r[j] = 1; q.append(j) } }
                    while let i = q.popLast() {
                        let x = i % w, y = i / w
                        if x > 0 { visit(i - 1) }
                        if x < w - 1 { visit(i + 1) }
                        if y > 0 { visit(i - w) }
                        if y < h - 1 { visit(i + w) }
                    }
                }
            }
        }
        for i in 0..<(w * h) where inside[i] != 0 && mask[i] == 0 && reach[i] == 0 { mask[i] = 1 }
        return mask
    }

    private static func dropSmallIslands(_ m: [UInt8], _ w: Int, _ h: Int, minCount: Int) -> [UInt8] {
        var label = [Int32](repeating: 0, count: w * h)
        var sizes: [Int] = [0]
        var next: Int32 = 1
        var stack: [Int] = []
        for start in 0..<(w * h) where m[start] != 0 && label[start] == 0 {
            label[start] = next; stack.append(start); var n = 0
            while let i = stack.popLast() {
                n += 1
                let x = i % w, y = i / w
                for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1] where j >= 0 && m[j] != 0 && label[j] == 0 {
                    label[j] = next; stack.append(j)
                }
            }
            sizes.append(n); next += 1
        }
        guard sizes.count > 2 else { return m }
        let largest = sizes.dropFirst().max() ?? 0
        var out = m
        for i in 0..<(w * h) where m[i] != 0 {
            let s = sizes[Int(label[i])]
            if s < minCount && s < largest { out[i] = 0 }
        }
        return out
    }
}

/// Separable square-kernel morphology on 8-bit 0/1 masks, shared by the segmenters.
enum Morphology {
    static func dilate(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var tmp = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where m[row + x] != 0 { for nx in max(0, x - r)...min(w - 1, x + r) { tmp[row + nx] = 1 } }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w {
            for y in 0..<h where tmp[y * w + x] != 0 { for ny in max(0, y - r)...min(h - 1, y + r) { out[ny * w + x] = 1 } }
        }
        return out
    }

    static func erode(_ m: [UInt8], _ w: Int, _ h: Int, _ r: Int) -> [UInt8] {
        guard r > 0 else { return m }
        var inv = m.map { $0 == 0 ? UInt8(1) : UInt8(0) }
        for x in 0..<w { inv[x] = 1; inv[(h - 1) * w + x] = 1 }
        for y in 0..<h { inv[y * w] = 1; inv[y * w + w - 1] = 1 }
        return dilate(inv, w, h, r).map { $0 == 0 ? UInt8(1) : UInt8(0) }
    }
}
