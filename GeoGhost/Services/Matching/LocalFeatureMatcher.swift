import CoreGraphics
import Foundation

/// ORB-style local feature matching: rotation-, scale- and occlusion-tolerant "is this the same design?"
///
/// Pipeline: grayscale pyramid → FAST-9 corners with Harris-like scores → intensity-centroid
/// orientation → rotated 256-bit BRIEF descriptors → Hamming matching with ratio test and
/// cross-check → RANSAC affine fit. The score is the number of geometrically consistent matches,
/// which stays high when a sticker is rotated, partly torn, or surrounded by extra background,
/// because consistent correspondences only come from the shared design.
enum LocalFeatureMatcher {
    struct Parameters: Sendable {
        var workingLongEdge = 512
        var pyramidLevels = 4
        var pyramidScale: Float = 1.25
        var fastThreshold: Int = 20
        var maxFeatures = 500
        var ratioTest: Float = 0.8
        var ransacIterations = 600
        var inlierThresholdPx: Float = 4
    }

    /// Serialized features for one image, cached per artwork.
    struct Features: Codable, Sendable {
        var width: Int
        var height: Int
        /// x, y, angle (radians), scale — flattened, 4 per keypoint, in working-image pixels.
        var keypoints: [Float]
        /// 256-bit descriptors, 4 UInt64 per keypoint.
        var descriptors: [UInt64]
        var count: Int { keypoints.count / 4 }

        func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
        static func decode(_ d: Data) -> Features? { try? JSONDecoder().decode(Features.self, from: d) }
    }

    struct MatchResult: Sendable {
        /// Raw descriptor matches that passed the ratio test and cross-check.
        var tentative: Int
        /// Matches consistent with the best affine transform.
        var inliers: Int
        /// inliers / min(keypoint count of either image) — normalizes small stickers.
        var inlierRatio: Float
        /// Rotation of the recovered transform, degrees, for diagnostics.
        var rotationDegrees: Float
    }

    // MARK: Feature extraction

    static func extract(_ image: CGImage, parameters p: Parameters = .init()) -> Features {
        let base = grayscale(image, maxLongEdge: p.workingLongEdge)
        var allKps: [(x: Float, y: Float, angle: Float, scale: Float, score: Float)] = []
        var allDesc: [UInt64] = []
        var level = base
        var scale: Float = 1
        for _ in 0..<p.pyramidLevels {
            guard level.w >= 48, level.h >= 48 else { break }
            let perLevel = max(40, p.maxFeatures / p.pyramidLevels)
            let kps = fastCorners(level, threshold: p.fastThreshold, maxCount: perLevel)
            for k in kps {
                let angle = orientation(level, x: k.x, y: k.y)
                let desc = brief(level, x: k.x, y: k.y, angle: angle)
                allKps.append((Float(k.x) * scale, Float(k.y) * scale, angle, scale, k.score))
                allDesc.append(contentsOf: desc)
            }
            level = downscale(level, by: p.pyramidScale)
            scale *= p.pyramidScale
        }
        // Keep the strongest overall.
        if allKps.count > p.maxFeatures {
            let order = allKps.indices.sorted { allKps[$0].score > allKps[$1].score }.prefix(p.maxFeatures)
            var kps: [Float] = [], desc: [UInt64] = []
            for i in order {
                kps += [allKps[i].x, allKps[i].y, allKps[i].angle, allKps[i].scale]
                desc += allDesc[(i * 4)..<(i * 4 + 4)]
            }
            return Features(width: base.w, height: base.h, keypoints: kps, descriptors: desc)
        }
        return Features(width: base.w, height: base.h,
                        keypoints: allKps.flatMap { [$0.x, $0.y, $0.angle, $0.scale] }, descriptors: allDesc)
    }

    // MARK: Matching

    static func match(_ a: Features, _ b: Features, parameters p: Parameters = .init()) -> MatchResult {
        let na = a.count, nb = b.count
        guard na >= 8, nb >= 8 else { return MatchResult(tentative: 0, inliers: 0, inlierRatio: 0, rotationDegrees: 0) }

        // Forward matches with Lowe ratio test.
        var forward = [Int](repeating: -1, count: na)
        var backward = [Int](repeating: -1, count: nb)
        a.descriptors.withUnsafeBufferPointer { da in
            b.descriptors.withUnsafeBufferPointer { db in
                for i in 0..<na {
                    var best = Int.max, second = Int.max, bestJ = -1
                    for j in 0..<nb {
                        let d = hamming(da, i, db, j)
                        if d < best { second = best; best = d; bestJ = j } else if d < second { second = d }
                    }
                    if bestJ >= 0, Float(best) < p.ratioTest * Float(second) { forward[i] = bestJ }
                }
                for j in 0..<nb {
                    var best = Int.max, bestI = -1
                    for i in 0..<na { let d = hamming(da, i, db, j); if d < best { best = d; bestI = i } }
                    backward[j] = bestI
                }
            }
        }
        var pairs: [(SIMD2<Float>, SIMD2<Float>)] = []
        for i in 0..<na where forward[i] >= 0 && backward[forward[i]] == i {
            let j = forward[i]
            pairs.append((SIMD2(a.keypoints[i * 4], a.keypoints[i * 4 + 1]), SIMD2(b.keypoints[j * 4], b.keypoints[j * 4 + 1])))
        }
        guard pairs.count >= 4 else { return MatchResult(tentative: pairs.count, inliers: 0, inlierRatio: 0, rotationDegrees: 0) }

        // RANSAC affine (3 correspondences).
        var rng = SplitMix64(seed: 0x5EED)
        var bestInliers = 0, bestRotation: Float = 0
        let thr2 = p.inlierThresholdPx * p.inlierThresholdPx
        for _ in 0..<p.ransacIterations {
            let i0 = Int(rng.next() % UInt64(pairs.count)), i1 = Int(rng.next() % UInt64(pairs.count)), i2 = Int(rng.next() % UInt64(pairs.count))
            guard i0 != i1, i1 != i2, i0 != i2, let T = affine(from: [pairs[i0].0, pairs[i1].0, pairs[i2].0], to: [pairs[i0].1, pairs[i1].1, pairs[i2].1]) else { continue }
            // Reject degenerate / wildly non-rigid fits: singular values within 0.4…2.5 of each other.
            let (sMin, sMax) = singularValues(T)
            guard sMin > 0.2, sMax / sMin < 2.5 else { continue }
            var inl = 0
            for (pa, pb) in pairs {
                let q = SIMD2(T.a * pa.x + T.c * pa.y + T.tx, T.b * pa.x + T.d * pa.y + T.ty)
                let e = q - pb
                if (e * e).sum() <= thr2 { inl += 1 }
            }
            if inl > bestInliers { bestInliers = inl; bestRotation = atan2(T.b, T.a) * 180 / .pi }
        }
        let ratio = Float(bestInliers) / Float(min(na, nb))
        return MatchResult(tentative: pairs.count, inliers: bestInliers, inlierRatio: ratio, rotationDegrees: bestRotation)
    }

    // MARK: - Internals

    struct Gray { var w: Int; var h: Int; var px: [UInt8] }

    static func grayscale(_ image: CGImage, maxLongEdge: Int) -> Gray {
        let long = max(image.width, image.height)
        let s = min(1, CGFloat(maxLongEdge) / CGFloat(long))
        let w = max(1, Int(CGFloat(image.width) * s)), h = max(1, Int(CGFloat(image.height) * s))
        var px = [UInt8](repeating: 128, count: w * h)
        px.withUnsafeMutableBytes { buf in
            // Grey canvas first so transparent cutout areas become neutral, not black.
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 0.5, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Gray(w: w, h: h, px: px)
    }

    static func downscale(_ g: Gray, by f: Float) -> Gray {
        let w = max(1, Int(Float(g.w) / f)), h = max(1, Int(Float(g.h) / f))
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let sy = min(g.h - 1, Int(Float(y) * f)), sy1 = min(g.h - 1, sy + 1)
            for x in 0..<w {
                let sx = min(g.w - 1, Int(Float(x) * f)), sx1 = min(g.w - 1, sx + 1)
                let v = (Int(g.px[sy * g.w + sx]) + Int(g.px[sy * g.w + sx1]) + Int(g.px[sy1 * g.w + sx]) + Int(g.px[sy1 * g.w + sx1])) / 4
                out[y * w + x] = UInt8(v)
            }
        }
        return Gray(w: w, h: h, px: out)
    }

    private static let circle: [(Int, Int)] = [(0, -3), (1, -3), (2, -2), (3, -1), (3, 0), (3, 1), (2, 2), (1, 3), (0, 3), (-1, 3), (-2, 2), (-3, 1), (-3, 0), (-3, -1), (-2, -2), (-1, -3)]

    /// FAST-9 with a simple contrast score and 3×3 non-maximum suppression.
    static func fastCorners(_ g: Gray, threshold t: Int, maxCount: Int) -> [(x: Int, y: Int, score: Float)] {
        let w = g.w, h = g.h, margin = 20
        guard w > 2 * margin, h > 2 * margin else { return [] }
        var scores = [Float](repeating: 0, count: w * h)
        g.px.withUnsafeBufferPointer { p in
            for y in margin..<(h - margin) {
                for x in margin..<(w - margin) {
                    let c = Int(p[y * w + x])
                    // Quick reject using the 4 compass points.
                    var brighter = 0, darker = 0
                    for k in [0, 4, 8, 12] { let v = Int(p[(y + circle[k].1) * w + x + circle[k].0]); if v > c + t { brighter += 1 } else if v < c - t { darker += 1 } }
                    guard brighter >= 3 || darker >= 3 else { continue }
                    var ring = [Int](repeating: 0, count: 16)
                    for k in 0..<16 { ring[k] = Int(p[(y + circle[k].1) * w + x + circle[k].0]) }
                    // 9 contiguous brighter or darker.
                    func run(_ pred: (Int) -> Bool) -> Bool {
                        var longest = 0, cur = 0
                        for k in 0..<32 { if pred(ring[k % 16]) { cur += 1; longest = max(longest, cur) } else { cur = 0 } }
                        return longest >= 9
                    }
                    if run({ $0 > c + t }) || run({ $0 < c - t }) {
                        var s: Float = 0
                        for v in ring { s += Float(abs(v - c)) }
                        scores[y * w + x] = s
                    }
                }
            }
        }
        var out: [(x: Int, y: Int, score: Float)] = []
        for y in margin..<(h - margin) {
            for x in margin..<(w - margin) {
                let s = scores[y * w + x]; guard s > 0 else { continue }
                var isMax = true
                outer: for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) { if scores[(y + dy) * w + x + dx] >= s && !(dx == 0 && dy == 0) && (scores[(y + dy) * w + x + dx] > s || (dy < 0 || (dy == 0 && dx < 0))) { isMax = false; break outer } } }
                if isMax { out.append((x, y, s)) }
            }
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(maxCount))
    }

    /// Intensity-centroid orientation over a radius-15 patch.
    static func orientation(_ g: Gray, x: Int, y: Int) -> Float {
        var m10: Float = 0, m01: Float = 0
        let r = 15
        for dy in -r...r {
            let yy = y + dy; guard yy >= 0, yy < g.h else { continue }
            let span = Int((Float(r * r - dy * dy)).squareRoot())
            for dx in -span...span {
                let xx = x + dx; guard xx >= 0, xx < g.w else { continue }
                let v = Float(g.px[yy * g.w + xx])
                m10 += Float(dx) * v; m01 += Float(dy) * v
            }
        }
        return atan2(m01, m10)
    }

    /// 256 fixed sampling pairs in a 31×31 patch (deterministic Gaussian-ish pattern).
    private static let briefPattern: [(Int8, Int8, Int8, Int8)] = {
        var rng = SplitMix64(seed: 0xB21EF)
        var pts: [(Int8, Int8, Int8, Int8)] = []
        func g() -> Int8 { // approx N(0, 31/5) clamped to ±13
            var s: Float = 0
            for _ in 0..<4 { s += Float(rng.next() % 1000) / 1000 - 0.5 }
            return Int8(max(-13, min(13, Int((s * 2 * 6.2).rounded()))))
        }
        for _ in 0..<256 { pts.append((g(), g(), g(), g())) }
        return pts
    }()

    static func brief(_ g: Gray, x: Int, y: Int, angle: Float) -> [UInt64] {
        let c = cos(angle), s = sin(angle)
        var out = [UInt64](repeating: 0, count: 4)
        @inline(__always) func sample(_ px: Int8, _ py: Int8) -> UInt8 {
            let rx = Int((Float(px) * c - Float(py) * s).rounded()), ry = Int((Float(px) * s + Float(py) * c).rounded())
            let xx = min(g.w - 1, max(0, x + rx)), yy = min(g.h - 1, max(0, y + ry))
            return g.px[yy * g.w + xx]
        }
        for (i, t) in briefPattern.enumerated() where sample(t.0, t.1) < sample(t.2, t.3) {
            out[i / 64] |= 1 << UInt64(i % 64)
        }
        return out
    }

    @inline(__always) private static func hamming(_ a: UnsafeBufferPointer<UInt64>, _ i: Int, _ b: UnsafeBufferPointer<UInt64>, _ j: Int) -> Int {
        (a[i * 4] ^ b[j * 4]).nonzeroBitCount + (a[i * 4 + 1] ^ b[j * 4 + 1]).nonzeroBitCount
            + (a[i * 4 + 2] ^ b[j * 4 + 2]).nonzeroBitCount + (a[i * 4 + 3] ^ b[j * 4 + 3]).nonzeroBitCount
    }

    struct Affine { var a: Float, b: Float, c: Float, d: Float, tx: Float, ty: Float }

    /// Exact affine from 3 correspondences (solve 3×3 twice).
    static func affine(from s: [SIMD2<Float>], to t: [SIMD2<Float>]) -> Affine? {
        let det = s[0].x * (s[1].y - s[2].y) - s[1].x * (s[0].y - s[2].y) + s[2].x * (s[0].y - s[1].y)
        guard abs(det) > 1e-3 else { return nil }
        func solve(_ r: [Float]) -> (Float, Float, Float) {
            // Straightforward 3x3 inverse instead.
            let m = [[s[0].x, s[0].y, 1], [s[1].x, s[1].y, 1], [s[2].x, s[2].y, 1]]
            let inv = invert3(m)!
            let p = inv[0][0] * r[0] + inv[0][1] * r[1] + inv[0][2] * r[2]
            let q = inv[1][0] * r[0] + inv[1][1] * r[1] + inv[1][2] * r[2]
            let o = inv[2][0] * r[0] + inv[2][1] * r[1] + inv[2][2] * r[2]
            return (p, q, o)
        }
        let (a, c, tx) = solve([t[0].x, t[1].x, t[2].x])
        let (b, d, ty) = solve([t[0].y, t[1].y, t[2].y])
        guard a.isFinite, b.isFinite, c.isFinite, d.isFinite else { return nil }
        return Affine(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    static func invert3(_ m: [[Float]]) -> [[Float]]? {
        let a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard abs(det) > 1e-6 else { return nil }
        let D = -(b * i - c * h), E = a * i - c * g, F = -(a * h - b * g)
        let G = b * f - c * e, H = -(a * f - c * d), I = a * e - b * d
        return [[A / det, D / det, G / det], [B / det, E / det, H / det], [C / det, F / det, I / det]]
    }

    static func singularValues(_ T: Affine) -> (Float, Float) {
        let a = T.a, b = T.b, c = T.c, d = T.d
        let s1 = a * a + b * b + c * c + d * d
        let s2 = ((a * a + b * b - c * c - d * d) * (a * a + b * b - c * c - d * d) + 4 * (a * c + b * d) * (a * c + b * d)).squareRoot()
        let smax = ((s1 + s2) / 2).squareRoot(), smin = (max(0, (s1 - s2) / 2)).squareRoot()
        return (smin, smax)
    }
}

/// Small deterministic PRNG so RANSAC and the BRIEF pattern are reproducible.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
