import Foundation

/// Bundled practice photos for the first cut-out (add-cutout-coaching): original GeoGhost stickers composited
/// onto the owner's own street photos, easiest first. Made by scripts/make-coaching-samples.swift and checked
/// with scripts/check-coaching-cutout.swift. Practice pieces are never saved to the collection.
enum PracticeSamples {
    /// ① one sticker alone · ② one among several · ③ two side by side.
    static let names = ["practice-1-single", "practice-2-among-many", "practice-3-side-by-side"]

    static func photo(_ index: Int) -> Data? {
        let name = names[((index % names.count) + names.count) % names.count]
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }
}
