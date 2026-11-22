#if DEBUG
import CoreLocation
import Foundation
import ImageIO
import SwiftData
import UIKit

/// Debug-only: fill an empty store from a GeoGhost export folder (manifest.json + Images/), for App Store
/// screenshots and manual testing. Launch with `-seedExport /path/to/export/GeoGhost`.
/// Place names are re-geocoded so they come out in the current app language. Not compiled into Release.
enum DebugSeeder {
    @MainActor static func seedIfRequested(into context: ModelContext) async {
        await seedDemoSeriesIfRequested(into: context)
        guard let path = UserDefaults.standard.string(forKey: "seedExport") else { return }
        guard ((try? context.fetchCount(FetchDescriptor<Artwork>())) ?? 0) == 0 else { return }
        let root = URL(fileURLWithPath: path)
        struct Manifest: Decodable { let artworks: [ExportRecord] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: root.appending(path: "manifest.json")),
              let manifest = try? decoder.decode(Manifest.self, from: data) else {
            print("DebugSeeder: no readable manifest at \(path)")
            return
        }

        for record in manifest.artworks {
            let source = root.appending(path: "Images").appending(path: record.id.uuidString)
            let target = ImageStore.shared.directory(for: record.id)
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { continue }

            let a = Artwork(id: record.id, kind: ArtworkKind(rawValue: record.kind) ?? .sticker)
            a.createdAt = record.createdAt
            a.capturedAt = record.capturedAt
            a.latitude = record.latitude
            a.longitude = record.longitude
            a.heading = record.heading
            a.locationSource = record.latitude == nil ? .none : .device
            a.countryCode = record.countryCode
            a.placeName = record.placeName
            a.note = record.note
            a.segmentationMode = SegmentationMode(rawValue: record.segmentationMode) ?? .auto
            a.deviceModel = record.deviceModel
            if record.files.count == 3 {
                a.originalImageID = record.files[0]; a.cutoutImageID = record.files[1]; a.thumbnailImageID = record.files[2]
            }
            if let src = CGImageSourceCreateWithURL(target.appending(path: a.originalImageID) as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                a.imagePixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                a.imagePixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
            if let cutout = ImageStore.shared.loadImage(artworkID: a.id, imageID: a.cutoutImageID) {
                a.dominantColorHex = ImageProcessing.dominantColorHex(ImageProcessing.downsample(cutout, maxLongEdge: 64))
            }
            context.insert(a)
            if let c = a.coordinate, let place = await ReverseGeocoder.shared.lookup(c) {
                a.placeName = place.placeName
                a.localityName = place.locality
                a.countryCode = place.countryCode ?? a.countryCode
            }
        }
        try? context.save()
        print("DebugSeeder: imported \(manifest.artworks.count) pieces")
    }

    // MARK: - Demo series

    /// Debug-only: add two drawn series for trying series features by hand — one seen in Tokyo and
    /// Osaka, one seen five times around Koenji. Launch with `-seedDemoSeries YES`; does nothing
    /// once any series exists.
    @MainActor private static func seedDemoSeriesIfRequested(into context: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: "seedDemoSeries") else { return }
        guard ((try? context.fetchCount(FetchDescriptor<ArtSeries>())) ?? 0) == 0 else { return }

        struct Sighting { let place: String; let locality: String; let latitude: Double; let longitude: Double; let daysAgo: Double }
        let demos: [(title: String, color: UIColor, sightings: [Sighting])] = [
            ("Orange cat", UIColor(red: 1, green: 0.42, blue: 0.17, alpha: 1), [
                Sighting(place: "高円寺南", locality: "杉並区", latitude: 35.7023, longitude: 139.6497, daysAgo: 120),
                Sighting(place: "北沢", locality: "世田谷区", latitude: 35.6614, longitude: 139.6680, daysAgo: 73),
                Sighting(place: "中崎町", locality: "大阪市", latitude: 34.7077, longitude: 135.5058, daysAgo: 23),
            ]),
            ("", UIColor(red: 0.23, green: 0.55, blue: 0.95, alpha: 1), [
                Sighting(place: "高円寺南", locality: "杉並区", latitude: 35.7031, longitude: 139.6489, daysAgo: 60),
                Sighting(place: "高円寺北", locality: "杉並区", latitude: 35.7078, longitude: 139.6502, daysAgo: 52),
                Sighting(place: "阿佐谷南", locality: "杉並区", latitude: 35.7030, longitude: 139.6360, daysAgo: 41),
                Sighting(place: "中野", locality: "中野区", latitude: 35.7056, longitude: 139.6657, daysAgo: 30),
                Sighting(place: "高円寺南", locality: "杉並区", latitude: 35.6995, longitude: 139.6521, daysAgo: 19),
            ]),
        ]
        for demo in demos {
            let series = ArtSeries(title: demo.title)
            context.insert(series)
            for sighting in demo.sightings {
                let artwork = Artwork(kind: .sticker)
                let picture = demoPicture(color: demo.color)
                guard let cutout = picture.cutout.cgImage, let photo = picture.photo.jpegData(compressionQuality: 0.85),
                      let saved = try? await ImageStore.shared.save(artworkID: artwork.id, originalData: photo, originalExtension: "jpg", cutout: cutout) else { continue }
                artwork.originalImageID = saved.originalID
                artwork.cutoutImageID = saved.cutoutID
                artwork.thumbnailImageID = saved.thumbnailID
                artwork.capturedAt = Date().addingTimeInterval(-sighting.daysAgo * 86_400)
                artwork.createdAt = artwork.capturedAt ?? Date()
                artwork.latitude = sighting.latitude
                artwork.longitude = sighting.longitude
                artwork.locationSource = .device
                artwork.placeName = sighting.place
                artwork.localityName = sighting.locality
                artwork.countryCode = "JP"
                artwork.imagePixelWidth = Int(picture.photo.size.width)
                artwork.imagePixelHeight = Int(picture.photo.size.height)
                artwork.dominantColorHex = ImageProcessing.dominantColorHex(ImageProcessing.downsample(cutout, maxLongEdge: 64))
                context.insert(artwork)
                artwork.series = series
            }
        }
        try? context.save()
        print("DebugSeeder: added demo series")
    }

    /// A round sticker with a face, alone (the cutout) and on a grey wall (the photo).
    @MainActor private static func demoPicture(color: UIColor) -> (cutout: UIImage, photo: UIImage) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        func sticker(in rect: CGRect) {
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            color.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)).fill()
            UIColor(white: 0.1, alpha: 1).setFill()
            for x in [0.36, 0.64] {
                UIBezierPath(ovalIn: CGRect(x: rect.minX + rect.width * x - rect.width * 0.035, y: rect.minY + rect.height * 0.42,
                                            width: rect.width * 0.07, height: rect.width * 0.07)).fill()
            }
            let smile = UIBezierPath()
            smile.move(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.60))
            smile.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.60),
                               controlPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.68))
            smile.lineWidth = rect.width * 0.025
            smile.lineCapStyle = .round
            UIColor(white: 0.1, alpha: 1).setStroke()
            smile.stroke()
        }
        let cutoutFormat = format.copy() as! UIGraphicsImageRendererFormat
        cutoutFormat.opaque = false
        let cutout = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: cutoutFormat).image { _ in
            sticker(in: CGRect(x: 0, y: 0, width: 600, height: 600))
        }
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format).image { context in
            UIColor(white: 0.62, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
            UIColor(white: 0.48, alpha: 1).setFill()
            context.fill(CGRect(x: 420, y: 0, width: 360, height: 1600))
            sticker(in: CGRect(x: 380, y: 560, width: 440, height: 440))
        }
        return (cutout, photo)
    }
}
#endif