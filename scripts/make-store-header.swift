// Renders the App Store "Header and Search Results" universal image (5244×2950, 16:9, opaque PNG) per language.
// Usage: swift scripts/make-store-header.swift <sticker-cutouts-dir> <out-dir>
//   <sticker-cutouts-dir> holds transparent PNG cutouts, used in filename order (first = hero).
//
// One image, three crops (Apple doesn't document them; measured from App Store Connect's Device Preview, 2026-10):
//   • iPhone product page: a ~3:2 window, horizontally centred, starting at the TOP edge (≈ x 1250–4100, y 0–1900);
//     its upper third sits behind the status bar and the back/share buttons.
//   • Search results card: the whole 16:9 image, small.
//   • iPad/Mac product page: a 21:9 band through the middle.
// So the tagline and main stickers live in the iPhone window below the buttons; extra stickers outside it
// fill the search card and the wide header.
import AppKit
import UniformTypeIdentifiers

let W: CGFloat = 5244, H: CGFloat = 2950

/// Measured iPhone product-page window (y-down) and the part of it below the nav buttons.
let phoneWindow = CGRect(x: 1250, y: 0, width: 2850, height: 1900)
let clear = CGRect(x: phoneWindow.minX + 130, y: 740, width: phoneWindow.width - 260, height: 1060)

let taglines: [String: String] = [
    "en": "Every street\nsticker, cut out\nand kept.",
    "zh-Hans": "街头的每一张贴纸，\n抠下来，\n收进图鉴。",
    "ja": "街で見つけた\nステッカーを、\n切り抜いて図鑑に。",
]

/// Sticker placements in y-down canvas coordinates: centre, longest side, rotation. The first one is the hero.
let mainSlots: [(x: CGFloat, y: CGFloat, size: CGFloat, deg: CGFloat)] = [
    (3480, 1270, 700, -6),   // hero
    (3010, 930, 360, 9),
    (3860, 920, 340, -10),
    (3020, 1630, 360, -8),
    (3860, 1620, 340, 7),
]
let outerSlots: [(x: CGFloat, y: CGFloat, size: CGFloat, deg: CGFloat)] = [
    (560, 1000, 440, -10),
    (760, 1780, 400, 8),
    (480, 2470, 420, -6),
    (1900, 2420, 440, 6),
    (3100, 2480, 400, -9),
    (4680, 1060, 460, 10),
    (4700, 2260, 440, -7),
]

let args = CommandLine.arguments
let stickerDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let stickers = try! FileManager.default.contentsOfDirectory(at: stickerDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    .compactMap { NSImage(contentsOf: $0) }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// AppKit draws y-up; layout above is y-down.
func up(_ y: CGFloat) -> CGFloat { H - y }

func render(lang: String, to url: URL) {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    NSGradient(starting: color(0xFF7F45), ending: color(0xF2541B))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func place(_ img: NSImage, _ slot: (x: CGFloat, y: CGFloat, size: CGFloat, deg: CGFloat)) {
        let s = slot.size / max(img.size.width, img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        ctx.saveGState()
        ctx.translateBy(x: slot.x, y: up(slot.y))
        ctx.rotate(by: slot.deg * .pi / 180)
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 46, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        img.draw(in: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    // Outer stickers first (search card / wide header only), then the main cluster, hero last so it sits on top.
    let outer = stickers.dropFirst(mainSlots.count)
    for (img, slot) in zip(outer, outerSlots) { place(img, slot) }
    let main = Array(stickers.prefix(mainSlots.count))
    for i in main.indices.reversed() { place(main[i], mainSlots[i]) }

    // Tagline: left part of the clear zone, largest size whose longest line fits, vertically centred.
    let textWidth: CGFloat = 2650 - clear.minX
    let para = NSMutableParagraphStyle(); para.lineSpacing = 14
    let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    var size: CGFloat = 170
    var title: NSAttributedString
    repeat {
        title = NSAttributedString(string: taglines[lang]!, attributes: [.font: rounded(size, .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para])
        size -= 5
    } while title.boundingRect(with: NSSize(width: 10_000, height: 10_000), options: opts).width > textWidth
    let kicker = NSAttributedString(string: "GeoGhost", attributes: [.font: rounded(105, .bold), .foregroundColor: color(0xFFFFFF, 0.8)])
    let kb = kicker.boundingRect(with: NSSize(width: textWidth, height: 1000), options: opts)
    let tb = title.boundingRect(with: NSSize(width: textWidth, height: 3000), options: opts)
    let gap: CGFloat = 50
    let topDown = clear.midY - (kb.height + gap + tb.height) / 2
    kicker.draw(with: NSRect(x: clear.minX, y: up(topDown + kb.height), width: textWidth, height: kb.height), options: opts)
    title.draw(with: NSRect(x: clear.minX, y: up(topDown + kb.height + gap + tb.height), width: textWidth, height: tb.height), options: opts)

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
