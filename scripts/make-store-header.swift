// Renders the App Store "Header and Search Results" universal image (5244×2950, 16:9, opaque PNG) per language:
// tagline on the left, a scatter of real cutout stickers on the right, on the brand orange.
// The header crops to 21:9 and the search card to 3:2, so everything sits inside their overlap.
// Usage: swift scripts/make-store-header.swift <sticker-cutouts-dir> <out-dir>
//   <sticker-cutouts-dir> holds transparent PNG cutouts; they are placed in filename order.
import AppKit
import UniformTypeIdentifiers

let W: CGFloat = 5244, H: CGFloat = 2950
// Overlap of the 21:9 header crop (full width × 2247) and the 3:2 search crop (4425 × full height), minus a margin.
let safe = NSRect(x: (W - 4425) / 2 + 150, y: (H - 2247) / 2 + 150, width: 4425 - 300, height: 2247 - 300)

let taglines: [String: (title: String, kicker: String)] = [
    "en": ("Every street sticker,\ncut out and kept.", "GeoGhost"),
    "zh-Hans": ("街头的每一张贴纸，\n抠下来，收进图鉴。", "GeoGhost"),
    "ja": ("街で見つけたステッカーを、\n切り抜いて図鑑に。", "GeoGhost"),
]

let args = CommandLine.arguments
let stickerDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let stickerFiles = try! FileManager.default.contentsOfDirectory(at: stickerDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
let stickers = stickerFiles.compactMap { NSImage(contentsOf: $0) }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// Sticker slots in the right-hand collage area: centre (as fractions of the area), longest side, rotation.
let slots: [(x: CGFloat, y: CGFloat, size: CGFloat, deg: CGFloat)] = [
    (0.50, 0.52, 820, -6),   // hero, centre
    (0.15, 0.80, 560, 9),
    (0.86, 0.82, 600, -10),
    (0.14, 0.22, 560, -8),
    (0.84, 0.20, 580, 7),
    (0.50, 0.90, 480, 4),
    (0.50, 0.12, 480, -4),
    (0.92, 0.50, 420, 12),
    (0.08, 0.52, 420, -12),
]

func render(lang: String, to url: URL) {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    NSGradient(starting: color(0xFF7F45), ending: color(0xF2541B))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Left: kicker + tagline, vertically centred in the safe area.
    let textWidth: CGFloat = 2050
    let para = NSMutableParagraphStyle(); para.lineSpacing = 18
    let kicker = NSAttributedString(string: taglines[lang]!.kicker,
                                    attributes: [.font: rounded(120, .bold), .foregroundColor: color(0xFFFFFF, 0.78)])
    let title = NSAttributedString(string: taglines[lang]!.title,
                                   attributes: [.font: rounded(lang == "en" ? 200 : 170, .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para])
    let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    let kb = kicker.boundingRect(with: NSSize(width: textWidth, height: 1000), options: opts)
    let tb = title.boundingRect(with: NSSize(width: textWidth, height: 2000), options: opts)
    let gap: CGFloat = 60, blockH = kb.height + gap + tb.height
    let top = safe.midY + blockH / 2
    kicker.draw(with: NSRect(x: safe.minX, y: top - kb.height, width: textWidth, height: kb.height), options: opts)
    title.draw(with: NSRect(x: safe.minX, y: top - kb.height - gap - tb.height, width: textWidth, height: tb.height), options: opts)

    // Right: stickers scattered like on a wall, smallest first so the hero sits on top.
    let area = NSRect(x: safe.minX + 2150, y: safe.minY, width: safe.width - 2150, height: safe.height)
    for (i, slot) in zip(stickers.indices, slots).sorted(by: { $0.1.size < $1.1.size }) {
        let img = stickers[i]
        let s = slot.size / max(img.size.width, img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        ctx.saveGState()
        ctx.translateBy(x: area.minX + area.width * slot.x, y: area.minY + area.height * slot.y)
        ctx.rotate(by: slot.deg * .pi / 180)
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 50, color: NSColor.black.withAlphaComponent(0.32).cgColor)
        img.draw(in: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}

for lang in ["en", "zh-Hans", "ja"] {
    render(lang: lang, to: outDir.appending(path: "\(lang)/header.png"))
}
