import CoreGraphics
import Foundation
import os

/// Owns the on-disk image files. One directory per artwork under Application Support/Images.
actor ImageStore {
    struct SavedImages: Sendable {
        let originalID: String
        let cutoutID: String
        let thumbnailID: String
    }

    static let shared = ImageStore()
    static let thumbnailLongEdge = 400

    private let root: URL
    private let log = Logger(subsystem: "com.passerbo.geoghost", category: "ImageStore")

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appending(path: "Images", directoryHint: .isDirectory)
        }
    }

    nonisolated func directory(for artworkID: UUID) -> URL {
        root.appending(path: artworkID.uuidString, directoryHint: .isDirectory)
    }

    nonisolated func url(artworkID: UUID, imageID: String) -> URL {
        directory(for: artworkID).appending(path: imageID)
    }

    /// Persist original bytes untouched (keeps EXIF) plus the cutout and a thumbnail.
    func save(artworkID: UUID, originalData: Data, originalExtension: String, cutout: CGImage) throws -> SavedImages {
        let dir = directory(for: artworkID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let originalID = "original.\(originalExtension)"
        try originalData.write(to: dir.appending(path: originalID), options: .atomic)

        guard let cutoutPNG = ImageProcessing.pngData(cutout) else { throw ImageStoreError.encodingFailed }
        try cutoutPNG.write(to: dir.appending(path: "cutout.png"), options: .atomic)

        let thumb = ImageProcessing.downsample(cutout, maxLongEdge: Self.thumbnailLongEdge)
        guard let thumbPNG = ImageProcessing.pngData(thumb) else { throw ImageStoreError.encodingFailed }
        try thumbPNG.write(to: dir.appending(path: "thumb.png"), options: .atomic)

        log.info("Saved images for \(artworkID.uuidString, privacy: .public)")
        return SavedImages(originalID: originalID, cutoutID: "cutout.png", thumbnailID: "thumb.png")
    }

    /// Overwrite cutout.png and thumb.png in place; the original is untouched.
    func replaceCutout(artworkID: UUID, cutout: CGImage) throws {
        let dir = directory(for: artworkID)
        guard let cutoutPNG = ImageProcessing.pngData(cutout) else { throw ImageStoreError.encodingFailed }
        try cutoutPNG.write(to: dir.appending(path: "cutout.png"), options: .atomic)
        let thumb = ImageProcessing.downsample(cutout, maxLongEdge: Self.thumbnailLongEdge)
        guard let thumbPNG = ImageProcessing.pngData(thumb) else { throw ImageStoreError.encodingFailed }
        try thumbPNG.write(to: dir.appending(path: "thumb.png"), options: .atomic)
    }

    func delete(artworkID: UUID) {
        let dir = directory(for: artworkID)
        try? FileManager.default.removeItem(at: dir)
    }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    nonisolated func loadImage(artworkID: UUID, imageID: String, maxPixelSize: Int? = nil) -> CGImage? {
        guard let data = try? Data(contentsOf: url(artworkID: artworkID, imageID: imageID)) else { return nil }
        return ImageProcessing.decodeUpright(data, maxPixelSize: maxPixelSize)
    }

    nonisolated func loadData(artworkID: UUID, imageID: String) -> Data? {
        try? Data(contentsOf: url(artworkID: artworkID, imageID: imageID))
    }

    /// Total bytes used by all stored images.
    func totalSize() -> Int64 {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Whether the volume has at least `minimumBytes` free for saving a new artwork.
    nonisolated func hasFreeSpace(minimumBytes: Int64 = 200 * 1024 * 1024) -> Bool {
        let values = try? root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return true }
        return free > minimumBytes
    }
}

enum ImageStoreError: LocalizedError {
    case encodingFailed
    var errorDescription: String? { String(localized: "Could not encode the image.") }
}
