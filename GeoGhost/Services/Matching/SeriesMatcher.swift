import Foundation

/// Decides whether a new cutout belongs to an existing series.
struct SeriesMatcher: Sendable {
    struct Candidate: Sendable {
        let artworkID: UUID
        let seriesID: UUID?
        let featurePrint: Data
    }

    enum Verdict: Sendable, Equatable {
        /// Confident match: join this series (or the series that will be created around this artwork).
        case match(artworkID: UUID, seriesID: UUID?, distance: Float)
        /// Grey zone: worth asking the user.
        case suggestion(artworkID: UUID, seriesID: UUID?, distance: Float)
        case none
    }

    /// Below this distance two prints are the same design.
    var matchThreshold: Float = 0.55
    /// Between match and this we surface a suggestion instead of auto-joining.
    var suggestionThreshold: Float = 0.75

    func evaluate(newPrint: Data, against candidates: [Candidate]) -> Verdict {
        var best: (Candidate, Float)?
        for c in candidates {
            guard let d = FeaturePrintService.distance(newPrint, c.featurePrint) else { continue }
            if best == nil || d < best!.1 { best = (c, d) }
        }
        guard let (c, d) = best else { return .none }
        if d < matchThreshold { return .match(artworkID: c.artworkID, seriesID: c.seriesID, distance: d) }
        if d < suggestionThreshold { return .suggestion(artworkID: c.artworkID, seriesID: c.seriesID, distance: d) }
        return .none
    }
}
