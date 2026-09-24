import Foundation

/// A portable snapshot of one artwork for the ZIP export.
struct ExportRecord: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var capturedAt: Date?
    var kind: String
    var latitude: Double?
    var longitude: Double?
    var heading: Double?
    var placeName: String?
    var countryCode: String?
    var note: String
    var tags: [String]
    var seriesID: UUID?
    var seriesTitle: String?
    var segmentationMode: String
    var deviceModel: String?
    var files: [String]

    @MainActor init(_ a: Artwork) {
        id = a.id; createdAt = a.createdAt; capturedAt = a.capturedAt; kind = a.kindRaw
        latitude = a.latitude; longitude = a.longitude; heading = a.heading
        placeName = a.placeName; countryCode = a.countryCode; note = a.note
        tags = a.tagList.map(\.name); seriesID = a.series?.id; seriesTitle = a.series?.title
        segmentationMode = a.segmentationModeRaw; deviceModel = a.deviceModel
        files = [a.originalImageID, a.cutoutImageID, a.thumbnailImageID]
    }
}

/// Builds `GeoGhost-Export.zip` containing manifest.json plus every image directory.
enum DataExporter {
    static func exportAll(records: [ExportRecord]) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "GeoGhost-Export-\(UUID().uuidString)")
        let root = staging.appending(path: "GeoGhost")
        try fm.createDirectory(at: root.appending(path: "Images"), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(["version": AnyCodable(1), "exportedAt": AnyCodable(ISO8601DateFormatter().string(from: Date())), "artworks": AnyCodable(records)])
            .write(to: root.appending(path: "manifest.json"))

        for r in records {
            let src = ImageStore.shared.directory(for: r.id)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: root.appending(path: "Images/\(r.id.uuidString)"))
            }
        }

        let zipURL = fm.temporaryDirectory.appending(path: "GeoGhost-Export.zip")
        try? fm.removeItem(at: zipURL)
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordError) { tmpZip in
            do { try fm.copyItem(at: tmpZip, to: zipURL) } catch { copyError = error }
        }
        try? fm.removeItem(at: staging)
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        return zipURL
    }
}

/// Tiny type-erased Codable for the manifest envelope.
struct AnyCodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
