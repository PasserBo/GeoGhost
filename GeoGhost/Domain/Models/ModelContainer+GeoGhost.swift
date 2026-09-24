import Foundation
import SwiftData

enum GeoGhostSchema {
    static let models: [any PersistentModel.Type] = [Artwork.self, ArtSeries.self, Tag.self]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        // SwiftData's default store lives in Application Support, which doesn't exist in a fresh container.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let config = ModelConfiguration("GeoGhost", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
