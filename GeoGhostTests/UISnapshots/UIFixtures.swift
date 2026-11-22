import CoreGraphics
import SwiftData
import UIKit
@testable import GeoGhost

/// Fixed data for UI snapshots: the same pieces, dates and pictures on every run, so two images
/// differ only when the UI changed. The pictures are drawn here rather than photographed, so they
/// can be committed and published (real street art can't be).
///
/// Fixtures are named in ui/screen.yaml (`fixture:`). Add one by adding a case to `make`.
@MainActor
final class UIFixture {
    let name: String
    let container: ModelContainer
    private var artworks: [String: Artwork] = [:]
    private var series: [String: ArtSeries] = [:]

    var context: ModelContext { container.mainContext }

    fileprivate init(name: String) throws {
        self.name = name
        container = try GeoGhostSchema.makeContainer(inMemory: true)
    }

    func artwork(_ key: String) -> Artwork {
        guard let artwork = artworks[key] else { fatalError("Fixture \(name) has no artwork \(key)") }
        return artwork
    }

    func series(_ key: String) -> ArtSeries {
        guard let series = series[key] else { fatalError("Fixture \(name) has no series \(key)") }
        return series
    }

    /// The name a piece was added under.
    func key(of artwork: Artwork) -> String {
        guard let key = artworks.first(where: { $0.value.id == artwork.id })?.key else { fatalError("Fixture \(name) doesn't hold this artwork") }
        return key
    }

    /// The sticker picture of a piece, as the share card wants it.
    func sticker(_ key: String) -> UIImage {
        let artwork = artwork(key)
        guard let image = ImageCache.shared.image(for: "\(artwork.id.uuidString)/\(artwork.cutoutImageID)") else {
            fatalError("Fixture \(name) has no picture for \(key)")
        }
        return UIImage(cgImage: image)
    }

    fileprivate func add(_ key: String, _ artwork: Artwork, picture: CGImage) {
        artworks[key] = artwork
        context.insert(artwork)
        // The app reads pictures from disk through this cache; filling it keeps fixtures off the disk.
        for imageID in [artwork.thumbnailImageID, artwork.cutoutImageID, artwork.originalImageID] {
            ImageCache.shared.set(picture, for: "\(artwork.id.uuidString)/\(imageID)")
        }
    }

    fileprivate func add(_ key: String, _ series: ArtSeries, members: [String]) {
        self.series[key] = series
        context.insert(series)
        for member in members { artwork(member).series = series }
    }
}

@MainActor
enum UIFixtures {
    static let names = ["empty", "typical"]

    static func make(_ name: String) throws -> UIFixture {
        let fixture = try UIFixture(name: name)
        switch name {
        case "empty": break
        case "typical": fillTypical(fixture)
        default: throw UnknownFixture(name: name)
        }
        try fixture.context.save()
        return fixture
    }

    struct UnknownFixture: Error { let name: String }

    // MARK: - typical: ten pieces, two series

    private struct Piece {
        let key: String
        let kind: ArtworkKind
        let shape: FixturePicture.Shape
        let hex: String
        /// Fixture time, Tokyo.
        let captured: String
        var place: String?
        var locality: String?
        var coordinate: (Double, Double)?
        var note = ""
        var tags: [String] = []
        var favorite = false
        var handCrop = false
    }

    private static let typical: [Piece] = [
        Piece(key: "cat-1", kind: .sticker, shape: .cat, hex: "#FF6B2C", captured: "2026-03-02T10:12:00",
              place: "高円寺南", locality: "杉並区", coordinate: (35.7023, 139.6497), note: "电线杆上，离地一米五。", tags: ["cat", "orange"], favorite: true),
        Piece(key: "cat-2", kind: .sticker, shape: .cat, hex: "#FF6B2C", captured: "2026-04-18T16:40:00",
              place: "北沢", locality: "世田谷区", coordinate: (35.6614, 139.6680)),
        Piece(key: "cat-3", kind: .sticker, shape: .cat, hex: "#FF6B2C", captured: "2026-06-07T13:05:00",
              place: "中崎町", locality: "大阪市", coordinate: (34.7077, 135.5058)),
        Piece(key: "ghost-1", kind: .tag, shape: .ghost, hex: "#3A8DF2", captured: "2026-05-11T19:22:00",
              note: "从相册导入，没有位置。和另一张应该是同一个人画的。", tags: ["ghost", "blue", "import"]),
        Piece(key: "ghost-2", kind: .tag, shape: .ghost, hex: "#3A8DF2", captured: "2026-05-29T08:48:00"),
        Piece(key: "mural-1", kind: .mural, shape: .stripes, hex: "#219E8C", captured: "2026-02-14T11:30:00",
              place: "東品川", locality: "品川区", coordinate: (35.6220, 139.7480), handCrop: true),
        Piece(key: "poster-1", kind: .poster, shape: .roundedSquare, hex: "#F0B824", captured: "2026-07-01T09:15:00",
              place: "神田佐久間町", locality: "千代田区", coordinate: (35.6980, 139.7730)),
        Piece(key: "graffiti-1", kind: .graffiti, shape: .star, hex: "#8C5CF5", captured: "2026-07-20T21:02:00",
              place: "宇田川町", locality: "渋谷区", coordinate: (35.6610, 139.6980), favorite: true),
        Piece(key: "sticker-2", kind: .sticker, shape: .hexagon, hex: "#E8457A", captured: "2026-08-03T12:44:00",
              place: "西新宿", locality: "新宿区", coordinate: (35.6938, 139.6920)),
        Piece(key: "other-1", kind: .other, shape: .circle, hex: "#8C8C94", captured: "2026-08-15T17:30:00"),
    ]

    private static func fillTypical(_ fixture: UIFixture) {
        for (index, piece) in typical.enumerated() {
            let artwork = Artwork(id: id(artwork: index + 1), kind: piece.kind)
            let captured = date(piece.captured)
            artwork.capturedAt = captured
            artwork.createdAt = captured.addingTimeInterval(30)
            if let (latitude, longitude) = piece.coordinate {
                artwork.latitude = latitude
                artwork.longitude = longitude
                artwork.horizontalAccuracy = 8
                artwork.heading = 82
                artwork.locationSource = .device
                artwork.countryCode = "JP"
            }
            artwork.placeName = piece.place
            artwork.localityName = piece.locality
            artwork.note = piece.note
            artwork.isFavorite = piece.favorite
            artwork.segmentationMode = piece.handCrop ? .manualCrop : .auto
            artwork.deviceModel = "iPhone 17 Pro"
            artwork.imagePixelWidth = 4032
            artwork.imagePixelHeight = 3024
            artwork.dominantColorHex = piece.hex
            fixture.add(piece.key, artwork, picture: FixturePicture.draw(piece.shape, hex: piece.hex))
            for name in piece.tags {
                let tag = Tag(name: name)
                tag.createdAt = captured
                fixture.context.insert(tag)
                artwork.tags = (artwork.tags ?? []) + [tag]
            }
        }

        let cats = ArtSeries(id: id(series: 1), title: "橙色猫")
        cats.createdAt = date("2026-04-18T16:41:00")
        fixture.add("cat", cats, members: ["cat-1", "cat-2", "cat-3"])

        // Untitled, and none of its pieces has a location.
        let ghosts = ArtSeries(id: id(series: 2))
        ghosts.createdAt = date("2026-05-29T08:49:00")
        fixture.add("ghost", ghosts, members: ["ghost-1", "ghost-2"])
    }

    // MARK: - Fixed values

    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        formatter.timeZone = timeZone
        guard let date = formatter.date(from: text) else { fatalError("Bad fixture date \(text)") }
        return date
    }

    static func id(artwork index: Int) -> UUID { UUID(uuidString: String(format: "A0000000-0000-4000-8000-%012d", index))! }
    static func id(series index: Int) -> UUID { UUID(uuidString: String(format: "50000000-0000-4000-8000-%012d", index))! }
    static func id(post index: Int) -> UUID { UUID(uuidString: String(format: "B0000000-0000-4000-8000-%012d", index))! }
}

// MARK: - Pictures

/// Simple sticker-like drawings: a coloured shape with a white die-cut border on a transparent
/// background. Plain enough to be obviously placeholders, varied enough to tell pieces apart.
enum FixturePicture {
    enum Shape { case cat, ghost, star, hexagon, circle, roundedSquare, stripes }

    static func draw(_ shape: Shape, hex: String, side: Int = 600) -> CGImage {
        let size = CGFloat(side)
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw with a top-left origin, like the rest of UIKit.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        let color = UIColor(hex: hex) ?? .gray
        let white = UIColor.white.cgColor
        let ink = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1).cgColor

        if shape == .stripes {
            // A hand crop: an opaque rectangle straight from the photo.
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setFillColor(white.copy(alpha: 0.35)!)
            for i in stride(from: -size, to: size * 2, by: 120) {
                context.move(to: CGPoint(x: i, y: 0))
                context.addLine(to: CGPoint(x: i + 60, y: 0))
                context.addLine(to: CGPoint(x: i + 60 - size, y: size))
                context.addLine(to: CGPoint(x: i - size, y: size))
                context.closePath()
                context.fillPath()
            }
            return context.makeImage()!
        }

        let outline = path(shape, in: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 70, dy: 70))
        context.setLineJoin(.round)
        context.addPath(outline)
        context.setStrokeColor(white)
        context.setLineWidth(56)
        context.strokePath()
        context.addPath(outline)
        context.setFillColor(color.cgColor)
        context.fillPath()

        // A face, so the shape reads as a character rather than a blank swatch.
        context.setFillColor(ink)
        for x in [size * 0.40, size * 0.60] {
            context.fillEllipse(in: CGRect(x: x - 16, y: size * 0.47, width: 32, height: 32))
        }
        context.setStrokeColor(ink)
        context.setLineWidth(10)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: size * 0.5, y: size * 0.58), radius: 34, startAngle: 0.25 * .pi, endAngle: 0.75 * .pi, clockwise: false)
        context.strokePath()
        return context.makeImage()!
    }

    /// A photo for the capture flow: two stickers on a tiled wall.
    static func photo() -> CGImage {
        let width = 1200, height = 1600
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor(red: 0.62, green: 0.63, blue: 0.64, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(UIColor(red: 0.50, green: 0.51, blue: 0.52, alpha: 1).cgColor)
        context.setLineWidth(6)
        for y in stride(from: 0, through: height, by: 200) {
            context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: width, y: y))
        }
        for x in stride(from: 0, through: width, by: 300) {
            context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: height))
        }
        context.strokePath()
        context.draw(draw(.cat, hex: "#FF6B2C"), in: CGRect(x: 250, y: 620, width: 700, height: 700))
        context.draw(draw(.star, hex: "#8C5CF5"), in: CGRect(x: 760, y: 180, width: 320, height: 320))
        return context.makeImage()!
    }

    static func photoData() -> Data {
        UIImage(cgImage: photo()).jpegData(compressionQuality: 0.9)!
    }

    static func pngData(_ shape: Shape, hex: String) -> Data {
        UIImage(cgImage: draw(shape, hex: hex)).pngData()!
    }

    private static func path(_ shape: Shape, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        func polygon(points: Int, innerRatio: CGFloat, rotation: CGFloat) {
            let count = innerRatio < 1 ? points * 2 : points
            for i in 0..<count {
                let r = (innerRatio < 1 && i % 2 == 1) ? radius * innerRatio : radius
                let angle = rotation + CGFloat(i) * 2 * .pi / CGFloat(count)
                let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        switch shape {
        case .circle:
            path.addEllipse(in: rect)
        case .roundedSquare:
            path.addRoundedRect(in: rect.insetBy(dx: 20, dy: 20), cornerWidth: 70, cornerHeight: 70)
        case .star:
            polygon(points: 5, innerRatio: 0.55, rotation: -.pi / 2)
        case .hexagon:
            polygon(points: 6, innerRatio: 1, rotation: 0)
        case .cat:
            // A round head with two ears.
            let head = rect.insetBy(dx: 10, dy: 40).offsetBy(dx: 0, dy: 40)
            path.addEllipse(in: head)
            for side: CGFloat in [-1, 1] {
                path.move(to: CGPoint(x: center.x + side * head.width * 0.46, y: head.minY + head.height * 0.38))
                path.addLine(to: CGPoint(x: center.x + side * head.width * 0.40, y: rect.minY))
                path.addLine(to: CGPoint(x: center.x + side * head.width * 0.10, y: head.minY + head.height * 0.10))
                path.closeSubpath()
            }
        case .ghost:
            // A dome on top, a wavy hem below.
            let body = rect.insetBy(dx: 40, dy: 0)
            path.move(to: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + body.width / 2))
            path.addArc(center: CGPoint(x: body.midX, y: body.minY + body.width / 2), radius: body.width / 2,
                        startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
            let step = body.width / 6
            for i in 1...6 {
                let x = body.maxX - CGFloat(i) * step
                path.addQuadCurve(to: CGPoint(x: x, y: body.maxY),
                                  control: CGPoint(x: x + step / 2, y: body.maxY + (i % 2 == 0 ? 40 : -40)))
            }
            path.closeSubpath()
        case .stripes:
            path.addRect(rect)
        }
        return path
    }
}
