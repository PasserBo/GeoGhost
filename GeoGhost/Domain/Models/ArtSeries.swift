import CoreLocation
import Foundation
import SwiftData

/// A group of artworks that share the same design (the same sticker seen in several places).
@Model
final class ArtSeries {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String = ""
    var coverArtworkID: UUID?
    @Attribute(.externalStorage) var representativeFeaturePrint: Data?

    @Relationship(deleteRule: .nullify, inverse: \Artwork.series) var artworks: [Artwork]? = []

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}

extension ArtSeries {
    var members: [Artwork] { (artworks ?? []).sorted { $0.displayDate < $1.displayDate } }

    var cover: Artwork? {
        if let coverArtworkID, let c = members.first(where: { $0.id == coverArtworkID }) { return c }
        return members.first
    }

    var encounterCount: Int { artworks?.count ?? 0 }

    var firstSeen: Date? { members.first?.displayDate }
    var lastSeen: Date? { members.last?.displayDate }

    var distinctLocalities: [String] {
        var seen = Set<String>()
        return members.compactMap { $0.localityName ?? $0.placeName }.filter { seen.insert($0).inserted }
    }

    var coordinates: [CLLocationCoordinate2D] { members.compactMap(\.coordinate) }

    var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled series") : title
    }
}
