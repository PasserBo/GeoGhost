// Renders the GeoGhost app icon (light, dark, tinted) as 1024×1024 PNGs.
// Usage: swift scripts/make-app-icon.swift GeoGhost/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Ghost silhouette in a 1024 canvas (y down): dome head, straight sides, three scallops at the hem.
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

struct Palette { let bgTop, bgBottom, ghost, back, eye: CGColor?; let shadow: CGFloat }

func render(_ pal: Palette, name: String) {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // The App Store rejects a light icon with an alpha channel; dark/tinted need transparency.
                        bitmapInfo: (pal.bgTop == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    // Flip to y-down so the geometry above reads naturally.
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    if let top = pal.bgTop, let bottom = pal.bgBottom {
        let g = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: [])
    }

    // Tilt the sticker a little, around the canvas centre.
    ctx.translateBy(x: S / 2, y: S / 2 + 20); ctx.rotate(by: -8 * .pi / 180); ctx.translateBy(x: -S / 2, y: -S / 2)

    let ghost = ghostPath()
    // Fold line across the bottom-right corner: A on the right side, B on the hem.
    let A = CGPoint(x: 790, y: 600), B = CGPoint(x: 655, y: 865)
    let d = CGPoint(x: B.x - A.x, y: B.y - A.y)
    /// Half-plane on one side of line AB, as a big quad. `towardCorner` = the side holding the lifted corner.
    func halfPlane(towardCorner: Bool) -> CGPath {
        let far: CGFloat = 4000
        let dl = (d.x * d.x + d.y * d.y).squareRoot()
        let dv = CGPoint(x: d.x / dl * far, y: d.y / dl * far)
        let sign: CGFloat = towardCorner ? 1 : -1   // (d.y, -d.x) points down-right, toward the corner
        let u = CGPoint(x: d.y / dl * far * sign, y: -d.x / dl * far * sign)
        let p0 = CGPoint(x: A.x - dv.x, y: A.y - dv.y), p1 = CGPoint(x: B.x + dv.x, y: B.y + dv.y)
        let path = CGMutablePath()
        path.addLines(between: [p0, p1, CGPoint(x: p1.x + u.x, y: p1.y + u.y), CGPoint(x: p0.x + u.x, y: p0.y + u.y)])
        path.closeSubpath()
        return path
    }
    let bodySide = halfPlane(towardCorner: false), cornerSide = halfPlane(towardCorner: true)

    // Reflection across line AB.
    let theta = atan2(d.y, d.x)
    let reflect = CGAffineTransform(translationX: A.x, y: A.y).rotated(by: theta).scaledBy(x: 1, y: -1).rotated(by: -theta).translatedBy(x: -A.x, y: -A.y)

    // 1. Sticker body (minus the lifted corner), with a soft drop shadow.
    if let ghostColor = pal.ghost {
        ctx.saveGState()
        // Shadow offsets are in device space (y up), unaffected by the flip above.
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: CGColor(gray: 0, alpha: pal.shadow))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(bodySide); ctx.clip()
        ctx.addPath(ghost); ctx.setFillColor(ghostColor); ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // 2. Eyes.
    if let eye = pal.eye {
        ctx.setFillColor(eye)
        ctx.fillEllipse(in: CGRect(x: 395, y: 400, width: 82, height: 118))
        ctx.fillEllipse(in: CGRect(x: 557, y: 400, width: 82, height: 118))
    }

    // 3. The peeled flap: the clipped-off corner, mirrored over the fold, showing the sticker's back.
    if let back = pal.back {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -10, height: -14), blur: 22, color: CGColor(gray: 0, alpha: pal.shadow * 0.8))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.concatenate(reflect)
        ctx.addPath(cornerSide); ctx.clip()
        ctx.addPath(ghost); ctx.setFillColor(back); ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    let img = ctx.makeImage()!
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}

let accentTop: UInt32 = 0xFF7F45, accentBottom: UInt32 = 0xF2541B
let paper: UInt32 = 0xFFF8EE, ink: UInt32 = 0x1F1C1A, backside: UInt32 = 0xE3DACB

// Light: orange ground, cream sticker.
render(Palette(bgTop: rgb(accentTop), bgBottom: rgb(accentBottom), ghost: rgb(paper), back: rgb(backside), eye: rgb(ink), shadow: 0.28), name: "AppIcon.png")
// Dark: transparent ground (the system supplies the dark backdrop), orange sticker.
render(Palette(bgTop: nil, bgBottom: nil, ghost: rgb(0xFF6B2B), back: rgb(0xB8481C), eye: rgb(0x1A1A1C), shadow: 0.5), name: "AppIcon-Dark.png")
// Tinted: grayscale on transparent; the system recolours it.
render(Palette(bgTop: nil, bgBottom: nil, ghost: rgb(0xFFFFFF), back: rgb(0x9A9A9A), eye: rgb(0x000000, 1), shadow: 0.35), name: "AppIcon-Tinted.png")
