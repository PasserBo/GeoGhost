#if DEBUG
import CoreLocation
import Foundation
import ImageIO
import SwiftData

/// Debug-only: fill an empty store from a GeoGhost export folder (manifest.json + Images/), for App Store
/// screenshots and manual testing. Launch with `-seedExport /path/to/export/GeoGhost`.
/// Place names are re-geocoded so they come out in the current app language. Not compiled into Release.
enum DebugSeeder {
    @MainActor static func seedIfRequested(into context: ModelContext) async {
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
}
#endif
