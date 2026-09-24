import SwiftUI

/// Small in-memory cache so grids don't decode PNGs on every scroll.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.countLimit = 600 }
    func image(for key: String) -> CGImage? { cache.object(forKey: key as NSString) }
    func set(_ image: CGImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
    func remove(prefix: String) { cache.removeAllObjects() }
}

/// Loads one of an artwork's stored images asynchronously.
struct ArtworkImageView: View {
    enum Variant { case thumbnail, cutout, original }

    let artwork: Artwork
    var variant: Variant = .thumbnail
    var contentMode: ContentMode = .fit

    @State private var image: CGImage?

    private var imageID: String {
        switch variant {
        case .thumbnail: artwork.thumbnailImageID
        case .cutout: artwork.cutoutImageID
        case .original: artwork.originalImageID
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .task(id: "\(artwork.id.uuidString)/\(imageID)") {
            let id = artwork.id, imageID = self.imageID
            let key = "\(id.uuidString)/\(imageID)"
            if let cached = ImageCache.shared.image(for: key) { image = cached; return }
            let maxPx: Int? = variant == .original ? 2048 : nil
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageStore.shared.loadImage(artworkID: id, imageID: imageID, maxPixelSize: maxPx)
            }.value
            if let loaded {
                ImageCache.shared.set(loaded, for: key)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
        }
    }
}

/// A cutout presented like a sticker in an album: soft drop shadow, no frame.
struct StickerCard: View {
    let artwork: Artwork
    var showsBadge = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ArtworkImageView(artwork: artwork, variant: .thumbnail)
                .padding(10)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)
                .background {
                    if !artwork.segmentationMode.isTransparent {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.paperElevated)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            .padding(6)
                    }
                }
            if showsBadge, let count = artwork.series?.encounterCount, count > 1 {
                Text("×\(count)")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.ink, in: Capsule())
                    .foregroundStyle(Theme.paper)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
    }
}
