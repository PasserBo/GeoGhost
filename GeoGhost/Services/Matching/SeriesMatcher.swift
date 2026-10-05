import Foundation

/// Decides whether a new cutout belongs to an existing series.
///
/// Primary signal: geometrically consistent local-feature matches (`LocalFeatureMatcher`), which
/// survive rotation, partial damage and extra background. Vision's global FeaturePrint is only a
/// fallback for legacy artworks that have no cached features yet.
struct SeriesMatcher: Sendable {
    struct Candidate: Sendable {
        let artworkID: UUID
        let seriesID: UUID?
        var featurePrint: Data?
        var localFeatures: Data?
    }

    enum Verdict: Sendable, Equatable {
        /// Confident match: join this series (or the series that will be created around this artwork).
        case match(artworkID: UUID, seriesID: UUID?, score: Float)
        /// Grey zone: worth asking the user.
        case suggestion(artworkID: UUID, seriesID: UUID?, score: Float)
        case none
    }

    /// Inlier matches at or above this are the same design (calibrated on a 50-piece set: no
    /// different-design pair exceeded 4).
    var matchInliers = 8
    /// Between this and `matchInliers` we surface a suggestion instead of auto-joining.
    var suggestionInliers = 5

    /// Legacy FeaturePrint thresholds (stricter than before; the embedding separates designs poorly).
    var fallbackMatchDistance: Float = 0.45
    var fallbackSuggestionDistance: Float = 0.6

    func evaluate(newFeatures: Data?, newPrint: Data?, against candidates: [Candidate]) -> Verdict {
        let mine = newFeatures.flatMap(LocalFeatureMatcher.Features.decode)
        var bestLocal: (Candidate, Int)?
        var bestPrint: (Candidate, Float)?
        for c in candidates {
            if let mine, let theirs = c.localFeatures.flatMap(LocalFeatureMatcher.Features.decode) {
                let r = LocalFeatureMatcher.match(mine, theirs)
                if bestLocal == nil || r.inliers > bestLocal!.1 { bestLocal = (c, r.inliers) }
            } else if let a = newPrint, let b = c.featurePrint, let d = FeaturePrintService.distance(a, b) {
                if bestPrint == nil || d < bestPrint!.1 { bestPrint = (c, d) }
            }
        }
        if let (c, inl) = bestLocal {
            if inl >= matchInliers { return .match(artworkID: c.artworkID, seriesID: c.seriesID, score: Float(inl)) }
            if inl >= suggestionInliers { return .suggestion(artworkID: c.artworkID, seriesID: c.seriesID, score: Float(inl)) }
        }
        if let (c, d) = bestPrint {
            if d < fallbackMatchDistance { return .match(artworkID: c.artworkID, seriesID: c.seriesID, score: 1 - d) }
            if d < fallbackSuggestionDistance { return .suggestion(artworkID: c.artworkID, seriesID: c.seriesID, score: 1 - d) }
        }
        return .none
    }
}
