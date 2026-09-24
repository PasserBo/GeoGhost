import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String = ""
    var createdAt: Date = Date()
    var artworks: [Artwork]? = []

    init(name: String) {
        self.name = Tag.normalize(name)
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }
}
