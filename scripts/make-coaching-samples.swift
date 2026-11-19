// Draws GeoGhost's own practice stickers (all derived from the app-icon ghost) and composites them into
// plain pole / metal areas of the owner's own street photos, for the add-cutout-coaching practice photos.
//
// Usage (from the repo root; compiled is much faster than `swift <file>`):
//   swiftc -O scripts/make-coaching-samples.swift -o /tmp/make-coaching-samples && /tmp/make-coaching-samples .
//
// Writes:
//   docs/spec/changes/add-cutout-coaching/stickers/*.png   sticker art (original, committed)
//   CoachingSamples/brand/{1,2,3}-*.jpg                    composites (local only: backgrounds are the owner's photos)
//   CoachingSamples/brand/{1,2,3}-*-cutout.png             ideal cutout of the target sticker
//   CoachingSamples/brand/{1,2,3}-*-mask.png               target's visible mask, full frame (for the Vision check)
//   CoachingSamples/brand/samples.json                     target tap point / box per sample (normalized, top-left origin)
// Reads backgrounds from AppStoreScreenshots/seed/Images/<id>/original.heic (local only).
// Deterministic: all randomness is seeded.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let stickerDir = root.appendingPathComponent("docs/spec/changes/add-cutout-coaching/stickers")
let outDir = root.appendingPathComponent("CoachingSamples/brand")
let seedImages = root.appendingPathComponent("AppStoreScreenshots/seed/Images")
try? FileManager.default.createDirectory(at: stickerDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// MARK: - Sticker art (design space y-down)

/// The app-icon ghost (same geometry as scripts/make-app-icon.swift).
func ghostPath() -> CGPath {
    let p = CGMutablePath()
    let cx: CGFloat = 512, top: CGFloat = 210, r: CGFloat = 270
    let left = cx - r, right = cx + r, hem: CGFloat = 760
    p.move(to: CGPoint(x: left, y: top + r))
    p.addArc(center: CGPoint(x: cx, y: top + r), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
    p.addLine(to: CGPoint(x: right, y: hem))
    let w = (right - left) / 3
    for i in (0..<3).reversed() {
        let x0 = left + CGFloat(i) * w
        p.addArc(center: CGPoint(x: x0 + w / 2, y: hem), radius: w / 2, startAngle: 0, endAngle: .pi, clockwise: false)
    }
    p.closeSubpath()
    return p
}

/// Map pin (teardrop), tip pointing down, as a sampled polygon.
func pinPath(center c: CGPoint, radius r: CGFloat, tilt: CGFloat) -> CGPath {
    let d = r * 1.9
    let half = acos(r / d)
    var pts: [CGPoint] = [CGPoint(x: 0, y: d)]
    let a0 = CGFloat.pi / 2 + half, a1 = CGFloat.pi / 2 - half + 2 * .pi
    for i in 0...48 {
        let a = a0 + (a1 - a0) * CGFloat(i) / 48
        pts.append(CGPoint(x: r * cos(a), y: r * sin(a)))
    }
    let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: tilt)
    let p = CGMutablePath()
    p.addLines(between: pts.map { $0.applying(t) })
    p.closeSubpath()
    return p
}

func starPath(center c: CGPoint, outer: CGFloat, inner: CGFloat, points n: Int = 4, rotation: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<(2 * n) {
        let r = i % 2 == 0 ? outer : inner
        let a = rotation - .pi / 2 + CGFloat(i) * .pi / CGFloat(n)
        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

let ink: UInt32 = 0x1F1C1A, paper: UInt32 = 0xFFF8EE

/// White die-cut border with a faint darker cut edge, following `shape` at `border` design units.
func drawDieCut(_ ctx: CGContext, _ shape: CGPath, border: CGFloat) {
    ctx.saveGState()
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.addPath(shape); ctx.setFillColor(rgb(0xD9D6D0)); ctx.fillPath()
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xD9D6D0)); ctx.setLineWidth(border * 2 + 5); ctx.strokePath()
    ctx.addPath(shape); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(border * 2); ctx.strokePath()
    ctx.restoreGState()
}

func fillStroke(_ ctx: CGContext, _ path: CGPath, fill: CGColor, stroke: CGColor = rgb(ink), width: CGFloat) {
    ctx.addPath(path); ctx.setFillColor(fill); ctx.fillPath()
    ctx.setLineJoin(.round)
    ctx.addPath(path); ctx.setStrokeColor(stroke); ctx.setLineWidth(width); ctx.strokePath()
}

struct GhostColors { let body, pin, pinHole, star, blush: UInt32 }

/// (a) Mascot die-cut: the icon ghost with a map pin and a sparkle, cut irregularly with a white border.
func drawGhostSticker(_ ctx: CGContext, _ c: GhostColors) {
    let ghost = ghostPath()
    let pin = pinPath(center: CGPoint(x: 790, y: 245), radius: 92, tilt: 0.32)
    let star = starPath(center: CGPoint(x: 205, y: 318), outer: 70, inner: 22, rotation: 0.2)
    let union = CGMutablePath(); union.addPath(ghost); union.addPath(pin); union.addPath(star)
    drawDieCut(ctx, union, border: 40)
    fillStroke(ctx, ghost, fill: rgb(c.body), width: 18)
    fillStroke(ctx, star, fill: rgb(c.star), width: 12)
    fillStroke(ctx, pin, fill: rgb(c.pin), width: 16)
    let hole = CGMutablePath(); hole.addEllipse(in: CGRect(x: 790 - 36, y: 245 - 36, width: 72, height: 72))
    fillStroke(ctx, hole.copy(using: nil)!, fill: rgb(c.pinHole), width: 12)
    // Face, from the icon: two tall eyes; plus highlights, blush and a small "oo" mouth.
    ctx.setFillColor(rgb(ink))
    ctx.fillEllipse(in: CGRect(x: 395, y: 400, width: 82, height: 118))
    ctx.fillEllipse(in: CGRect(x: 557, y: 400, width: 82, height: 118))
    ctx.fillEllipse(in: CGRect(x: 494, y: 545, width: 40, height: 50))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: 418, y: 418, width: 26, height: 30))
    ctx.fillEllipse(in: CGRect(x: 580, y: 418, width: 26, height: 30))
    ctx.setFillColor(rgb(c.blush, 0.85))
    ctx.fillEllipse(in: CGRect(x: 345, y: 535, width: 72, height: 38))
    ctx.fillEllipse(in: CGRect(x: 617, y: 535, width: 72, height: 38))
}

let roundedFontName = "Arial Rounded MT Bold"

func glyphs(_ text: String, size: CGFloat) -> [(path: CGPath?, advance: CGFloat)] {
    let font = CTFontCreateWithName(roundedFontName as CFString, size, nil)
    let chars = Array(text.utf16)
    var gs = [CGGlyph](repeating: 0, count: chars.count)
    CTFontGetGlyphsForCharacters(font, chars, &gs, chars.count)
    var adv = [CGSize](repeating: .zero, count: gs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, gs, &adv, gs.count)
    return gs.indices.map { (CTFontCreatePathForGlyph(font, gs[$0], nil), adv[$0].width) }
}

/// Glyph paths (y-up) laid along a circle; `top` = reads clockwise over the top, else left-to-right along the bottom.
func arcText(_ text: String, size: CGFloat, center c: CGPoint, radius R: CGFloat, top: Bool, tracking: CGFloat = 0) -> CGPath {
    let gl = glyphs(text, size: size)
    let font = CTFontCreateWithName(roundedFontName as CFString, size, nil)
    let capH = CTFontGetCapHeight(font)
    let total = gl.reduce(0) { $0 + $1.advance + tracking } - tracking
    let span = total / R
    let out = CGMutablePath()
    var cum: CGFloat = 0
    for g in gl {
        let mid = (cum + g.advance / 2) / R
        let theta = top ? -.pi / 2 - span / 2 + mid : .pi / 2 + span / 2 - mid
        let phi = top ? theta + .pi / 2 : theta - .pi / 2
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: phi).translatedBy(x: 0, y: top ? -R : R)
        t = t.translatedBy(x: -g.advance / 2, y: capH / 2).scaledBy(x: 1, y: -1)
        if let p = g.path { out.addPath(p, transform: t) }
        cum += g.advance + tracking
    }
    return out
}

struct BadgeColors { let ring, inner, ghost, text, star: UInt32 }

/// (b) Round badge: ring with GEOGHOST / STREET FINDS on the arc, the ghost in the middle.
func drawBadgeSticker(_ ctx: CGContext, _ c: BadgeColors) {
    let C = CGPoint(x: 512, y: 512)
    let disc = CGPath(ellipseIn: CGRect(x: C.x - 470, y: C.y - 470, width: 940, height: 940), transform: nil)
    drawDieCut(ctx, disc, border: 30)
    fillStroke(ctx, disc, fill: rgb(c.ring), width: 16)
    let inner = CGPath(ellipseIn: CGRect(x: C.x - 318, y: C.y - 318, width: 636, height: 636), transform: nil)
    fillStroke(ctx, inner, fill: rgb(c.inner), width: 14)
    ctx.setFillColor(rgb(c.text))
    ctx.addPath(arcText("GEOGHOST", size: 104, center: C, radius: 392, top: true, tracking: 10)); ctx.fillPath()
    ctx.addPath(arcText("STREET FINDS", size: 74, center: C, radius: 392, top: false, tracking: 6)); ctx.fillPath()
    for x in [C.x - 392, C.x + 392] {
        fillStroke(ctx, starPath(center: CGPoint(x: x, y: C.y), outer: 30, inner: 11), fill: rgb(c.star), width: 6)
    }
    // Small ghost, centred in the inner disc.
    ctx.saveGState()
    ctx.translateBy(x: C.x, y: C.y + 18); ctx.scaleBy(x: 0.62, y: 0.62); ctx.translateBy(x: -512, y: -575)
    fillStroke(ctx, ghostPath(), fill: rgb(c.ghost), width: 22)
    ctx.setFillColor(rgb(ink))
    ctx.fillEllipse(in: CGRect(x: 395, y: 400, width: 82, height: 118))
    ctx.fillEllipse(in: CGRect(x: 557, y: 400, width: 82, height: 118))
    ctx.restoreGState()
}

struct BubbleColors { let top, bottom, shade: UInt32 }

/// (c) Bubble letters ("throw-up" style): per-letter ink outline and puffy fill, a 3D drop, a white die-cut.
func bubbleLetters(_ text: String) -> (letters: [CGPath], union: CGPath) {
    let gl = glyphs(text, size: 300)
    var out: [CGPath] = []
    let union = CGMutablePath()
    var x: CGFloat = 0
    var rng = SeededRandom(seed: 7)
    for g in gl {
        let rot = CGFloat(rng.next() * 0.22 - 0.11)
        let s = CGFloat(0.95 + rng.next() * 0.16)
        let dy = CGFloat(rng.next() * 40 - 20)
        guard let p = g.path else { x += g.advance; continue }
        let b = p.boundingBoxOfPath
        var t = CGAffineTransform(translationX: x + g.advance / 2, y: 300 + dy).rotated(by: rot).scaledBy(x: s, y: -s)
        t = t.translatedBy(x: -b.midX, y: -b.midY)
        let letter = p.copy(using: &t)!
        out.append(letter); union.addPath(letter)
        x += g.advance * 0.9
    }
    return (out, union)
}

func drawBubbleSticker(_ ctx: CGContext, text: String, _ c: BubbleColors, origin: CGPoint) {
    ctx.translateBy(x: origin.x, y: origin.y)
    let (letters, union) = bubbleLetters(text)
    /// A path grown by w/2: the glyph and its stroke ring are painted separately so their windings never cancel.
    func paintGrown(_ p: CGPath, _ w: CGFloat, _ paint: () -> Void) {
        for part in [p, p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)] {
            ctx.saveGState(); ctx.addPath(part); ctx.clip(); paint(); ctx.restoreGState()
        }
    }
    let everything = CGRect(x: -2000, y: -2000, width: 8000, height: 8000)
    func solid(_ color: CGColor) -> () -> Void { { ctx.setFillColor(color); ctx.fill(everything) } }
    let drop = CGAffineTransform(translationX: 18, y: 22)
    let cut = CGMutablePath(); cut.addPath(union); cut.addPath(union, transform: drop)
    drawDieCut(ctx, cut, border: 35 + 34)
    // 3D drop: ink silhouette shifted, with the shade colour inside it.
    ctx.saveGState(); ctx.concatenate(drop)
    paintGrown(union, 70, solid(rgb(ink)))
    paintGrown(union, 30, solid(rgb(c.shade)))
    ctx.restoreGState()
    let b = union.boundingBoxOfPath.insetBy(dx: -30, dy: -30)
    let g = CGGradient(colorsSpace: sRGB, colors: [rgb(c.top), rgb(c.bottom)] as CFArray, locations: [0, 1])!
    // Letters left to right, each over the previous: ink outline, then the puffy fill and a shine.
    for letter in letters {
        paintGrown(letter, 70, solid(rgb(ink)))
        let r = letter.boundingBoxOfPath
        paintGrown(letter, 30) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: b.minY), end: CGPoint(x: 0, y: b.maxY), options: [])
            ctx.setFillColor(rgb(0xFFFFFF, 0.8))
            ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.08, y: r.minY - 4, width: r.width * 0.26, height: r.height * 0.12))
        }
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}

/// A sticker design: size of its design canvas and how to draw it.
struct Design {
    let name: String
    let size: CGSize
    let draw: (CGContext) -> Void
}

func ghostDesign(_ name: String, _ c: GhostColors) -> Design {
    Design(name: name, size: CGSize(width: 1024, height: 1024)) { drawGhostSticker($0, c) }
}
func badgeDesign(_ name: String, _ c: BadgeColors) -> Design {
    Design(name: name, size: CGSize(width: 1024, height: 1024)) { drawBadgeSticker($0, c) }
}
func bubbleDesign(_ name: String, text: String, _ c: BubbleColors) -> Design {
    let b = bubbleLetters(text).union.boundingBoxOfPath
    let pad: CGFloat = 120
    return Design(name: name, size: CGSize(width: b.width + pad * 2 + 20, height: b.height + pad * 2 + 20)) {
        drawBubbleSticker($0, text: text, c, origin: CGPoint(x: pad - b.minX, y: pad - b.minY))
    }
}

/// Renders a design at `scale` px per design unit into an RGBA image, trimmed to its opaque pixels.
func render(_ d: Design, scale: CGFloat) -> CGImage {
    let w = Int(ceil(d.size.width * scale)), h = Int(ceil(d.size.height * scale))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: scale, y: -scale)
    d.draw(ctx)
    let img = ctx.makeImage()!
    // Trim transparent margins (keep 2px).
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self), bpr = ctx.bytesPerRow
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where data[y * bpr + x * 4 + 3] > 0 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let r = CGRect(x: max(0, minX - 2), y: max(0, minY - 2), width: min(w, maxX + 3) - max(0, minX - 2), height: min(h, maxY + 3) - max(0, minY - 2))
    return img.cropping(to: r)!
}

func writePNG(_ img: CGImage, _ url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    precondition(CGImageDestinationFinalize(d))
}

func writeJPEG(_ img: CGImage, _ url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    precondition(CGImageDestinationFinalize(d))
}

// MARK: - Float image buffers (RGBA premultiplied, 0…1)

struct Buf {
    let w: Int, h: Int
    var p: [Float]
    init(w: Int, h: Int, channels: Int = 4) { self.w = w; self.h = h; p = [Float](repeating: 0, count: w * h * channels) }

    init(_ img: CGImage, width: Int? = nil, height: Int? = nil) {
        w = width ?? img.width; h = height ?? img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = ctx.data!.assumingMemoryBound(to: UInt8.self)
        p = (0..<(w * h * 4)).map { Float(d[$0]) / 255 }
    }

    func cgImage(opaque: Bool) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h * 4) { bytes[i] = UInt8(max(0, min(255, (p[i] * 255).rounded()))) }
        if opaque { for i in 0..<(w * h) { bytes[i * 4 + 3] = 255 } }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                            bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
        return ctx.makeImage()!
    }
}

func grayImage(_ a: [Float], w: Int, h: Int) -> CGImage {
    var bytes = a.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    return ctx.makeImage()!
}

/// Separable box blur (3 passes ≈ gaussian) of a single-channel plane.
func blur(_ a: [Float], w: Int, h: Int, radius r: Int, passes: Int = 3) -> [Float] {
    guard r > 0 else { return a }
    var src = a, dst = a
    let norm = 1 / Float(2 * r + 1)
    for _ in 0..<passes {
        for y in 0..<h {
            var s: Float = 0
            let row = y * w
            for k in -r...r { s += src[row + min(w - 1, max(0, k))] }
            for x in 0..<w {
                dst[row + x] = s * norm
                s += src[row + min(w - 1, x + r + 1)] - src[row + max(0, x - r)]
            }
        }
        for x in 0..<w {
            var s: Float = 0
            for k in -r...r { s += dst[min(h - 1, max(0, k)) * w + x] }
            for y in 0..<h {
                src[y * w + x] = s * norm
                s += dst[min(h - 1, y + r + 1) * w + x] - dst[max(0, y - r) * w + x]
            }
        }
    }
    return src
}

func luminance(_ b: Buf) -> [Float] {
    (0..<(b.w * b.h)).map { i in 0.2126 * b.p[i * 4] + 0.7152 * b.p[i * 4 + 1] + 0.0722 * b.p[i * 4 + 2] }
}

/// Smooth value noise, fbm.
func noise(_ x: Float, _ y: Float, seed: UInt32) -> Float {
    func hash(_ i: Int32, _ j: Int32) -> Float {
        var h = UInt32(bitPattern: i) &* 374761393 &+ UInt32(bitPattern: j) &* 668265263 &+ seed &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        return Float(h & 0xFFFF) / 65535
    }
    let xi = Int32(floor(x)), yi = Int32(floor(y))
    let fx = x - floor(x), fy = y - floor(y)
    let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
    let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
    return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
}
func fbm(_ x: Float, _ y: Float, seed: UInt32) -> Float {
    var s: Float = 0, amp: Float = 0.5, f: Float = 1
    for o in 0..<4 { s += amp * noise(x * f, y * f, seed: seed &+ UInt32(o)); amp *= 0.5; f *= 2.03 }
    return s / 0.9375
}

// MARK: - Perspective warp

struct Homography {
    var m: [Double]  // 3x3 row-major
    /// Unit square (0,0),(1,0),(1,1),(0,1) → quad q0…q3.
    init(quad q: [CGPoint]) {
        let x0 = Double(q[0].x), y0 = Double(q[0].y), x1 = Double(q[1].x), y1 = Double(q[1].y)
        let x2 = Double(q[2].x), y2 = Double(q[2].y), x3 = Double(q[3].x), y3 = Double(q[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        let den = dx1 * dy2 - dx2 * dy1
        let g = (dx3 * dy2 - dx2 * dy3) / den, h = (dx1 * dy3 - dx3 * dy1) / den
        m = [x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h, 1]
    }
    func inverse() -> Homography {
        let a = m
        let det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
        var r = Homography(quad: [.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)])
        r.m = [
            (a[4] * a[8] - a[5] * a[7]) / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
            (a[5] * a[6] - a[3] * a[8]) / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
            (a[3] * a[7] - a[4] * a[6]) / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det,
        ]
        return r
    }
    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
        let z = m[6] * x + m[7] * y + m[8]
        return ((m[0] * x + m[1] * y + m[2]) / z, (m[3] * x + m[4] * y + m[5]) / z)
    }
}

/// How a sticker sits in the photo.
struct Placement {
    let design: Design
    let center: CGPoint      // output px
    let width: CGFloat       // output px, before perspective
    let rotation: CGFloat    // degrees, clockwise
    let keystone: CGFloat    // >0: top edge narrower (camera looking up), fraction
    let skew: CGFloat        // >0: right edge taller (camera off to the left), fraction
    let wear: Float          // 0…1
    let seed: UInt32
}

struct Warped {
    var rgba: Buf            // premultiplied sticker colour in output frame
    var alpha: [Float]
    var uv: [Float]          // sticker-space u,v per pixel (for wear), 2 channels
    let bbox: (x0: Int, y0: Int, x1: Int, y1: Int)
}

func warp(_ pl: Placement, w W: Int, h H: Int) -> Warped {
    // Render at about 1.4× the on-screen size (trimmed to the die-cut), then sample.
    let img = render(pl.design, scale: pl.width * 1.4 / pl.design.size.width)
    let src = Buf(img)
    let wpx = CGFloat(img.width) / 1.4, hpx = CGFloat(img.height) / 1.4
    let hw = wpx / 2, hh = hpx / 2
    let k = pl.keystone, s = pl.skew
    var corners = [CGPoint(x: -hw * (1 - k), y: -hh * (1 - s)), CGPoint(x: hw * (1 - k), y: -hh * (1 + s)),
                   CGPoint(x: hw * (1 + k), y: hh * (1 + s)), CGPoint(x: -hw * (1 + k), y: hh * (1 - s))]
    let rot = pl.rotation * .pi / 180
    corners = corners.map { CGPoint(x: pl.center.x + $0.x * cos(rot) - $0.y * sin(rot), y: pl.center.y + $0.x * sin(rot) + $0.y * cos(rot)) }
    let inv = Homography(quad: corners).inverse()
    let x0 = max(0, Int(corners.map(\.x).min()!) - 2), x1 = min(W - 1, Int(corners.map(\.x).max()!) + 2)
    let y0 = max(0, Int(corners.map(\.y).min()!) - 2), y1 = min(H - 1, Int(corners.map(\.y).max()!) + 2)
    var out = Buf(w: W, h: H)
    var alpha = [Float](repeating: 0, count: W * H)
    var uv = [Float](repeating: -1, count: W * H * 2)
    let sW = src.w, sH = src.h
    func sample(_ fx: Double, _ fy: Double) -> (Float, Float, Float, Float) {
        let x = fx - 0.5, y = fy - 0.5
        let xi = Int(floor(x)), yi = Int(floor(y))
        let tx = Float(x - floor(x)), ty = Float(y - floor(y))
        var acc: (Float, Float, Float, Float) = (0, 0, 0, 0)
        for (dx, dy, wt) in [(0, 0, (1 - tx) * (1 - ty)), (1, 0, tx * (1 - ty)), (0, 1, (1 - tx) * ty), (1, 1, tx * ty)] {
            let sx = xi + dx, sy = yi + dy
            guard sx >= 0, sy >= 0, sx < sW, sy < sH else { continue }
            let i = (sy * sW + sx) * 4
            acc.0 += src.p[i] * wt; acc.1 += src.p[i + 1] * wt; acc.2 += src.p[i + 2] * wt; acc.3 += src.p[i + 3] * wt
        }
        return acc
    }
    let ss = [0.25, 0.75]
    for y in y0...y1 { for x in x0...x1 {
        var acc: (Float, Float, Float, Float) = (0, 0, 0, 0)
        var uu = 0.0, vv = 0.0
        for oy in ss { for ox in ss {
            let (u, v) = inv.apply(Double(x) + ox, Double(y) + oy)
            uu += u / 4; vv += v / 4
            guard u >= 0, v >= 0, u <= 1, v <= 1 else { continue }
            let c = sample(u * Double(sW), v * Double(sH))
            acc.0 += c.0 / 4; acc.1 += c.1 / 4; acc.2 += c.2 / 4; acc.3 += c.3 / 4
        } }
        let i = y * W + x
        out.p[i * 4] = acc.0; out.p[i * 4 + 1] = acc.1; out.p[i * 4 + 2] = acc.2; out.p[i * 4 + 3] = acc.3
        alpha[i] = acc.3
        uv[i * 2] = Float(uu); uv[i * 2 + 1] = Float(vv)
    } }
    return Warped(rgba: out, alpha: alpha, uv: uv, bbox: (x0, y0, x1, y1))
}

// MARK: - Scene

struct Patch { let rect: CGRect; let dx: Int; let dy: Int; let feather: CGFloat }

struct Scene {
    let name: String
    let photoID: String          // prefix of the seed image folder
    let crop: CGRect             // in the upright original
    let patches: [Patch]         // clone plain surface over anything that isn't plain (output px)
    let stickers: [Placement]    // bottom to top
    let target: Int
    let exposure: Float          // how bright white paper reads in this photo
    let softness: Int            // blur radius to match the photo's sharpness
}

func loadBackground(_ s: Scene) -> Buf {
    let folder = try! FileManager.default.contentsOfDirectory(atPath: seedImages.path).first { $0.hasPrefix(s.photoID) }!
    let url = seedImages.appendingPathComponent(folder).appendingPathComponent("original.heic")
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    // Upright (EXIF orientation applied); pixels only, no metadata travels further.
    let full = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4032] as CFDictionary)!
    let c = full.cropping(to: s.crop)!
    let scale = 2048 / max(s.crop.width, s.crop.height)
    return Buf(c, width: Int((s.crop.width * scale).rounded()), height: Int((s.crop.height * scale).rounded()))
}

func applyPatch(_ b: inout Buf, _ p: Patch) {
    let src = b
    let r = p.rect
    for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) {
        let sx = x + p.dx, sy = y + p.dy
        guard x >= 0, y >= 0, x < b.w, y < b.h, sx >= 0, sy >= 0, sx < b.w, sy < b.h else { continue }
        let d = min(CGFloat(x) - r.minX, r.maxX - CGFloat(x), CGFloat(y) - r.minY, r.maxY - CGFloat(y))
        let t = Float(min(1, d / p.feather)); let wt = t * t * (3 - 2 * t)
        for c in 0..<3 {
            let i = (y * b.w + x) * 4 + c
            b.p[i] = src.p[i] * (1 - wt) + src.p[(sy * b.w + sx) * 4 + c] * wt
        }
    } }
}

func compose(_ s: Scene) -> [String: Any] {
    var bg = loadBackground(s)
    for p in s.patches { applyPatch(&bg, p) }
    let W = bg.w, H = bg.h
    let lum = luminance(bg)
    let lumWide = blur(lum, w: W, h: H, radius: 60)       // local light level
    let lumFine = blur(lum, w: W, h: H, radius: 3)
    // Colour cast: the photo's average colour, normalised to unit luminance.
    var mean: (Float, Float, Float) = (0, 0, 0)
    for i in 0..<(W * H) { mean.0 += bg.p[i * 4]; mean.1 += bg.p[i * 4 + 1]; mean.2 += bg.p[i * 4 + 2] }
    let n = Float(W * H); mean = (mean.0 / n, mean.1 / n, mean.2 / n)
    let meanL = 0.2126 * mean.0 + 0.7152 * mean.1 + 0.0722 * mean.2
    let cast = [mean.0 / meanL, mean.1 / meanL, mean.2 / meanL].map { 1 + ($0 - 1) * 0.55 }
    let refL = lumWide.reduce(0, +) / n

    var img = bg
    var above = [Float](repeating: 0, count: W * H)   // coverage of stickers placed after the target
    var targetAlpha = [Float](repeating: 0, count: W * H)
    var rng = SeededRandom(seed: s.name.utf8.reduce(99) { $0 &* 31 &+ UInt64($1) })

    for (idx, pl) in s.stickers.enumerated() {
        var wp = warp(pl, w: W, h: H)
        let (x0, y0, x1, y1) = wp.bbox
        // Shadow: a soft one and a tight contact one.
        let soft = blur(wp.alpha, w: W, h: H, radius: 5), contact = blur(wp.alpha, w: W, h: H, radius: 1)
        for y in max(0, y0 - 30)...min(H - 1, y1 + 30) { for x in max(0, x0 - 30)...min(W - 1, x1 + 30) {
            let i = y * W + x
            let sa = soft[max(0, min(H - 1, y - 7)) * W + max(0, min(W - 1, x - 4))] * 0.32
            let ca = contact[max(0, y - 2) * W + max(0, x - 1)] * 0.28
            let k = (1 - sa) * (1 - ca)
            for c in 0..<3 { img.p[i * 4 + c] *= k }
        } }
        // Match the photo's sharpness.
        if s.softness > 0 {
            var planes = (0..<4).map { c in (0..<(W * H)).map { wp.rgba.p[$0 * 4 + c] } }
            planes = planes.map { blur($0, w: W, h: H, radius: s.softness, passes: 1) }
            for i in 0..<(W * H) { for c in 0..<4 { wp.rgba.p[i * 4 + c] = planes[c][i] } }
            wp.alpha = planes[3]
        }
        // Edge distance proxy for wear at the rim.
        let rim = blur(wp.alpha, w: W, h: H, radius: 6)
        for y in y0...y1 { for x in x0...x1 {
            let i = y * W + x
            let a = wp.alpha[i]
            guard a > 0.001 else { continue }
            var r = wp.rgba.p[i * 4] / a, g = wp.rgba.p[i * 4 + 1] / a, b = wp.rgba.p[i * 4 + 2] / a
            let u = wp.uv[i * 2], v = wp.uv[i * 2 + 1]
            // Wear: scuffs where the print is rubbed off (paper shows), grime, and a dirtier rim.
            let scuff = fbm(u * 9, v * 9, seed: pl.seed) , fine = fbm(u * 60, v * 60, seed: pl.seed &+ 11)
            let rub = max(0, min(1, (scuff * 0.6 + fine * 0.4 - (0.74 - pl.wear * 0.12)) * 7)) * pl.wear
            r += (0.93 - r) * rub; g += (0.92 - g) * rub; b += (0.9 - b) * rub
            let grime = 1 - pl.wear * 0.10 * fbm(u * 4, v * 4, seed: pl.seed &+ 5) - pl.wear * 0.18 * max(0, 1 - rim[i] * 1.15)
            // Light: exposure × local light level × colour cast, plus the surface texture showing through.
            let shade = pow(max(0.2, lumWide[i] / refL), 0.85)
            let tex = (lum[i] - lumFine[i]) * 0.5 + (lumFine[i] - lumWide[i]) * 0.12
            // A faint gloss band across the vinyl.
            let gloss = 0.035 * max(0, 1 - abs((u + v * 0.6) - 0.75) * 4)
            var col = [r, g, b]
            for c in 0..<3 {
                col[c] = col[c] * s.exposure * shade * cast[c] * grime + tex + gloss
                col[c] += Float(rng.next() - 0.5) * 0.022   // sensor grain
            }
            for c in 0..<3 { img.p[i * 4 + c] = img.p[i * 4 + c] * (1 - a) + max(0, min(1, col[c])) * a }
            if idx == s.target { targetAlpha[i] = a } else if idx > s.target { above[i] = 1 - (1 - above[i]) * (1 - a) }
        } }
    }
    for i in 0..<(W * H) { targetAlpha[i] *= 1 - above[i] }

    // Outputs.
    writeJPEG(img.cgImage(opaque: true), outDir.appendingPathComponent("\(s.name).jpg"))
    writePNG(grayImage(targetAlpha, w: W, h: H), outDir.appendingPathComponent("\(s.name)-mask.png"))
    var minX = W, minY = H, maxX = 0, maxY = 0
    var sx = 0.0, sy = 0.0, sa = 0.0
    for y in 0..<H { for x in 0..<W where targetAlpha[y * W + x] > 0.5 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        sx += Double(x); sy += Double(y); sa += 1
    } }
    var cut = Buf(w: maxX - minX + 1, h: maxY - minY + 1)
    for y in minY...maxY { for x in minX...maxX {
        let a = targetAlpha[y * W + x], j = ((y - minY) * cut.w + (x - minX)) * 4, i = (y * W + x) * 4
        for c in 0..<3 { cut.p[j + c] = img.p[i + c] * a }
        cut.p[j + 3] = a
    } }
    writePNG(cut.cgImage(opaque: false), outDir.appendingPathComponent("\(s.name)-cutout.png"))
    print("wrote \(s.name): \(W)×\(H), target \(s.stickers[s.target].design.name)")
    return [
        "name": s.name, "width": W, "height": H,
        "target": s.stickers[s.target].design.name,
        "tapPoint": [sx / sa / Double(W), sy / sa / Double(H)],
        "targetBox": [Double(minX) / Double(W), Double(minY) / Double(H), Double(maxX - minX) / Double(W), Double(maxY - minY) / Double(H)],
    ]
}

// MARK: - Designs and scenes

let orangeGhost = ghostDesign("ghost-orange", GhostColors(body: 0xFF6B2B, pin: paper, pinHole: 0xFF6B2B, star: 0xFFC93C, blush: 0xFFB08A))
let creamGhost = ghostDesign("ghost-cream", GhostColors(body: paper, pin: 0xFF6B2B, pinHole: paper, star: 0xFFC93C, blush: 0xFF9C6E))
let mintGhost = ghostDesign("ghost-mint", GhostColors(body: 0x7FDCC4, pin: 0x3D5AFE, pinHole: paper, star: 0xFFE066, blush: 0xFF8FB1))
let violetGhost = ghostDesign("ghost-violet", GhostColors(body: 0xB79CFF, pin: 0xFFC93C, pinHole: 0xB79CFF, star: 0x7FDCC4, blush: 0xFF8FB1))
let orangeBadge = badgeDesign("badge-orange", BadgeColors(ring: 0xFF6B2B, inner: paper, ghost: paper, text: paper, star: 0xFFC93C))
let blueBadge = badgeDesign("badge-blue", BadgeColors(ring: 0x2F4BD8, inner: 0xFFE066, ghost: paper, text: paper, star: 0xFF8FB1))
let blueBubble = bubbleDesign("bubble-blue", text: "GEOGHOST", BubbleColors(top: 0x6E8BFF, bottom: 0x2F4BD8, shade: 0x18267A))
let pinkBubble = bubbleDesign("bubble-pink", text: "GEOGHOST", BubbleColors(top: 0xFFB3CB, bottom: 0xFF5C8A, shade: 0x9C1F4A))
let mintBubble = bubbleDesign("bubble-mint", text: "BOO", BubbleColors(top: 0xB8F5E4, bottom: 0x3CC9A4, shade: 0x1B6B57))

let designs = [orangeGhost, creamGhost, mintGhost, violetGhost, orangeBadge, blueBadge, blueBubble, pinkBubble, mintBubble]

let scenes: [Scene] = [
    // ① One sticker alone on a clean pole (Shibuya). The original throw-up in this spot is cloned out with
    //    plain pole from below it; the ghost then covers the spot.
    Scene(name: "1-easy-single", photoID: "10B4", crop: CGRect(x: 0, y: 0, width: 2760, height: 3680),
          patches: [Patch(rect: CGRect(x: 300, y: 790, width: 980, height: 640), dx: 0, dy: 600, feather: 60),
                    Patch(rect: CGRect(x: 860, y: 300, width: 140, height: 150), dx: 0, dy: -120, feather: 30)],
          stickers: [Placement(design: orangeGhost, center: CGPoint(x: 790, y: 1090), width: 880, rotation: -6,
                               keystone: 0.03, skew: -0.02, wear: 0.5, seed: 11)],
          target: 0, exposure: 0.86, softness: 0),
    // ② The target ghost among several other GeoGhost stickers on a metal box.
    Scene(name: "2-one-among-many", photoID: "3C08", crop: CGRect(x: 814, y: 2322, width: 1189, height: 1710),
          patches: [],
          stickers: [
            Placement(design: pinkBubble, center: CGPoint(x: 720, y: 330), width: 1180, rotation: -4, keystone: 0.02, skew: 0.01, wear: 0.8, seed: 21),
            Placement(design: blueBadge, center: CGPoint(x: 1080, y: 1580), width: 470, rotation: 14, keystone: 0.02, skew: 0, wear: 0.6, seed: 22),
            Placement(design: violetGhost, center: CGPoint(x: 330, y: 1680), width: 400, rotation: 9, keystone: 0.02, skew: 0, wear: 0.7, seed: 23),
            Placement(design: mintBubble, center: CGPoint(x: 1120, y: 950), width: 420, rotation: 8, keystone: 0.02, skew: 0, wear: 0.9, seed: 24),
            Placement(design: orangeGhost, center: CGPoint(x: 470, y: 1000), width: 560, rotation: -5, keystone: 0.02, skew: 0, wear: 0.4, seed: 25),
          ],
          target: 4, exposure: 0.84, softness: 1),
    // ③ Two stickers touching on a zinc pole: the ghost overlaps the round badge.
    Scene(name: "3-two-touching", photoID: "8070", crop: CGRect(x: 626, y: 2855, width: 2392, height: 1177),
          patches: [],
          stickers: [
            Placement(design: orangeBadge, center: CGPoint(x: 800, y: 510), width: 620, rotation: -8, keystone: 0.02, skew: 0.02, wear: 0.6, seed: 31),
            Placement(design: creamGhost, center: CGPoint(x: 1335, y: 500), width: 600, rotation: 7, keystone: 0.02, skew: 0.02, wear: 0.4, seed: 32),
          ],
          target: 1, exposure: 0.8, softness: 0),
]

for d in designs { writePNG(render(d, scale: 1), stickerDir.appendingPathComponent("\(d.name).png")) }
print("wrote \(designs.count) sticker PNGs to \(stickerDir.path)")

let only = CommandLine.arguments.dropFirst(2).first
var meta: [[String: Any]] = []
for s in scenes where only == nil || s.name.hasPrefix(only!) { meta.append(compose(s)) }
if only == nil {
    let json = try! JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
    try! json.write(to: outDir.appendingPathComponent("samples.json"))
}
