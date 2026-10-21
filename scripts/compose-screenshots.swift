// Composes App Store screenshots: a caption on the brand orange above the whole framed phone screen.
// Usage: swift scripts/compose-screenshots.swift <raw-dir> <out-dir>
//   <raw-dir>/<lang>/<n>.png  — raw simulator screenshots from an iPhone 17 Pro (1206×2622; lang: en, zh-Hans, ja; n: 1…5)
//   <out-dir>/<lang>/<n>.png  — 1206×2622 opaque PNGs: "iPhone with Dynamic Island (medium display)",
//                               the only iPhone size App Store Connect takes for this app (checked 2026-10).
import AppKit
import UniformTypeIdentifiers

let captions: [String: [String]] = [
    "en": [
        "Every sticker you spot,\ncut out and kept",
        "Where and when,\nrecorded for you",
        "Meet a sticker again?\nIt joins a series",
        "Your city,\npiece by piece",
        "Share your finds\nas cards",
    ],
    "zh-Hans": [
        "街头的每一张贴纸\n抠下来，收进图鉴",
        "在哪里、什么时候\n自动帮你记下",
        "再次遇见同一张贴纸\n自动归为系列",
        "一点一点\n拼出你的城市",
        "把你的发现\n做成卡片分享",
    ],
    "ja": [
        "街で見つけたステッカーを\n切り抜いて図鑑に",
        "どこで、いつ見つけたか\n自動で記録",
        "同じステッカーに再会したら\nシリーズにまとまる",
        "自分の街を\n一枚ずつ",
        "見つけた作品を\nカードでシェア",
    ],
]

let W: CGFloat = 1206, H: CGFloat = 2622
let args = CommandLine.arguments
let rawDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func compose(raw: NSImage, caption: String, langDir: URL, fileName: String) {
    // No alpha channel: App Store screenshots must be opaque.
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    // Background: the icon's orange gradient (AppKit is y-up, so "top" is maxY).
    NSGradient(starting: color(0xFF7F45), ending: color(0xF2541B))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Caption, centred near the top.
    let fontSize: CGFloat = 78
    let base = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: fontSize) ?? base
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 6
    let text = NSAttributedString(string: caption, attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para])
    let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    let textWidth = W - 110
    let bounds = text.boundingRect(with: NSSize(width: textWidth, height: 600), options: opts)
    let captionTop: CGFloat = 130
    let captionRect = NSRect(x: (W - textWidth) / 2, y: H - captionTop - bounds.height, width: textWidth, height: bounds.height)
    text.draw(with: captionRect, options: opts)

    // The whole phone screen below it: a fixed gap under the caption, a margin above the bottom edge.
    let gap: CGFloat = 70, bottomMargin: CGFloat = 80, bezel: CGFloat = 13
    let sh = captionRect.minY - gap - bottomMargin - 2 * bezel
    let sw = sh * raw.size.width / raw.size.height
    let frame = NSRect(x: (W - sw) / 2, y: bottomMargin + bezel, width: sw, height: sh)
    let radius = sw * 0.087
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 55, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), xRadius: radius + bezel, yRadius: radius + bezel).fill()
    ctx.restoreGState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    raw.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    let image = ctx.makeImage()!
    write(image, to: langDir.appending(path: fileName))
}

func write(_ image: CGImage, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}

for (lang, list) in captions {
    for (i, caption) in list.enumerated() {
        let raw = rawDir.appending(path: "\(lang)/\(i + 1).png")
        guard let image = NSImage(contentsOf: raw) else { print("skip (missing)", raw.path); continue }
        compose(raw: image, caption: caption, langDir: outDir.appending(path: lang), fileName: "\(i + 1).png")
    }
}
