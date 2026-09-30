import CoreGraphics
import Foundation
import SwiftData

/// Writes a new artwork, then enriches it in the background (feature print, series, place).
@MainActor
enum ArtworkSaver {
    struct Input {
        var originalData: Data
        var originalExtension: String
        var cutout: CGImage
        var cutoutRect: CGRect
        var segmentationMode: SegmentationMode
        var metadata: CaptureMetadata
        var kind: ArtworkKind
        var kindIsUserSet: Bool
        var note: String
        var tags: [String]
        var place: PlaceInfo?
    }

    static func save(_ input: Input, in context: ModelContext) async throws {
        guard ImageStore.shared.hasFreeSpace() else { throw SaveError.lowDiskSpace }

        let artwork = Artwork(kind: input.kind)
        artwork.apply(input.metadata)
        artwork.kindIsUserSet = input.kindIsUserSet
        artwork.kindIsAutoDetected = !input.kindIsUserSet
        artwork.cutoutRect = input.cutoutRect
        artwork.segmentationMode = input.segmentationMode
        artwork.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let place = input.place {
            artwork.placeName = place.placeName
            artwork.localityName = place.locality
            artwork.countryCode = place.countryCode
        }

        let id = artwork.id
        let cutout = input.cutout
        let saved = try await ImageStore.shared.save(artworkID: id, originalData: input.originalData, originalExtension: input.originalExtension, cutout: cutout)
        artwork.originalImageID = saved.originalID
        artwork.cutoutImageID = saved.cutoutID
        artwork.thumbnailImageID = saved.thumbnailID

        context.insert(artwork)
        artwork.tags = try Self.tags(named: input.tags, in: context)
        try context.save()

        // Background enrichment; each step saves independently so the UI updates as results land.
        Task { await enrich(artworkID: id, cutout: cutout, needsPlace: input.place == nil, context: context) }
    }

    /// Swap an artwork's cutout for a new one from the same photo; metadata and relations are untouched.
    /// The feature print is recomputed so series matching reflects the new cutout.
    static func replaceCutout(of artwork: Artwork, with cutout: CGImage, rect: CGRect, mode: SegmentationMode, in context: ModelContext) async throws {
        let id = artwork.id
        try await ImageStore.shared.replaceCutout(artworkID: id, cutout: cutout)
        ImageCache.shared.remove(prefix: id.uuidString)
        artwork.cutoutRect = rect
        artwork.segmentationMode = mode
        try context.save()

        let printAndColor = await Task.detached(priority: .utility) { () -> (Data?, String?) in
            (try? FeaturePrintService.featurePrint(for: cutout), ImageProcessing.dominantColorHex(ImageProcessing.downsample(cutout, maxLongEdge: 64)))
        }.value
        artwork.featurePrint = printAndColor.0
        artwork.dominantColorHex = printAndColor.1
        try? context.save()
        if let print = printAndColor.0, artwork.series == nil {
            await SeriesAssigner.assign(artwork, print: print, in: context)
        }
    }

    static func tags(named names: [String], in context: ModelContext) throws -> [Tag] {
        var result: [Tag] = []
        for raw in names {
            let name = Tag.normalize(raw)
            guard !name.isEmpty else { continue }
            let predicate = #Predicate<Tag> { $0.name == name }
            if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                if !result.contains(where: { $0.name == name }) { result.append(existing) }
            } else {
                let t = Tag(name: name)
                context.insert(t)
                result.append(t)
            }
        }
        return result
    }

    private static func enrich(artworkID: UUID, cutout: CGImage, needsPlace: Bool, context: ModelContext) async {
        // 1. Feature print + colour.
        let printAndColor = await Task.detached(priority: .utility) { () -> (Data?, String?) in
            (try? FeaturePrintService.featurePrint(for: cutout), ImageProcessing.dominantColorHex(ImageProcessing.downsample(cutout, maxLongEdge: 64)))
        }.value
        guard let artwork = fetch(artworkID, in: context) else { return }
        artwork.featurePrint = printAndColor.0
        artwork.dominantColorHex = printAndColor.1
        try? context.save()

        // 2. Series matching.
        if let print = printAndColor.0 {
            await SeriesAssigner.assign(artwork, print: print, in: context)
        }

        // 3. Place, if the save sheet didn't manage it in time.
        if needsPlace, let c = artwork.coordinate {
            if let place = await ReverseGeocoder.shared.lookup(c), let a = fetch(artworkID, in: context) {
                a.placeName = place.placeName
                a.localityName = place.locality
                a.countryCode = place.countryCode
                try? context.save()
            }
        }
    }

    static func fetch(_ id: UUID, in context: ModelContext) -> Artwork? {
        let predicate = #Predicate<Artwork> { $0.id == id }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    enum SaveError: LocalizedError {
        case lowDiskSpace
        var errorDescription: String? { String(localized: "Not enough free storage to save this piece.") }
    }
}

/// Puts an artwork into the right series based on its feature print.
@MainActor
enum SeriesAssigner {
    static var matcher = SeriesMatcher()

    static func assign(_ artwork: Artwork, print: Data, in context: ModelContext) async {
        guard !artwork.isSeriesManuallyAssigned else { return }
        let id = artwork.id
        let others = (try? context.fetch(FetchDescriptor<Artwork>())) ?? []
        let candidates = others.compactMap { o -> SeriesMatcher.Candidate? in
            guard o.id != id, let fp = o.featurePrint else { return nil }
            return .init(artworkID: o.id, seriesID: o.series?.id, featurePrint: fp)
        }
        guard !candidates.isEmpty else { return }
        let m = matcher
        let verdict = await Task.detached(priority: .utility) { m.evaluate(newPrint: print, against: candidates) }.value
        guard case .match(let otherID, let seriesID, _) = verdict else { return }

        if let seriesID, let series = fetchSeries(seriesID, in: context) {
            artwork.series = series
        } else if let other = ArtworkSaver.fetch(otherID, in: context) {
            let series = ArtSeries()
            series.coverArtworkID = other.id
            series.representativeFeaturePrint = other.featurePrint
            context.insert(series)
            other.series = series
            artwork.series = series
        }
        try? context.save()
    }

    static func fetchSeries(_ id: UUID, in context: ModelContext) -> ArtSeries? {
        let predicate = #Predicate<ArtSeries> { $0.id == id }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// Re-run matching for every artwork that isn't manually assigned (used after threshold changes).
    static func rematchAll(in context: ModelContext) async {
        let all = (try? context.fetch(FetchDescriptor<Artwork>())) ?? []
        for a in all where a.series == nil && !a.isSeriesManuallyAssigned {
            if let fp = a.featurePrint { await assign(a, print: fp, in: context) }
        }
    }
}
