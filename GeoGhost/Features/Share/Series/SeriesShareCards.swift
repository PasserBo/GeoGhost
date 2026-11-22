import SwiftUI

/// The cards a series can be shared as. To add one: draw it, then return another option here.
@MainActor
enum SeriesShareCards {
    /// The cards on offer, the one to show first leading.
    static func options(for content: SeriesCardContent) -> [ShareCardOption] {
        leads(for: content.stats).map { lead in
            ShareCardOption(id: lead.optionID, title: lead.title) { SeriesShareCard(content: content, lead: lead) }
        }
    }

    /// A distance card needs a distance. When there is one, it leads if the design crossed cities.
    nonisolated static func leads(for stats: SeriesStats) -> [SeriesShareCard.Lead] {
        guard stats.distanceMeters != nil else { return [.encounters] }
        return stats.isCrossCity ? [.distance, .encounters] : [.encounters, .distance]
    }
}

extension SeriesShareCard.Lead {
    var optionID: String { "series-\(rawValue)" }

    var title: LocalizedStringResource {
        switch self {
        case .distance: "Distance"
        case .encounters: "Encounters"
        }
    }
}
