import SwiftData
import SwiftUI

/// Share a series: prepares what its cards show, lets the user pick the picture and the name, and
/// hands the cards to the deck.
struct SeriesShareSheet: View {
    @Bindable var series: ArtSeries

    @Environment(\.modelContext) private var context
    @Query(sort: \ArtSeries.createdAt) private var allSeries: [ArtSeries]
    @State private var coverID: UUID?
    @State private var usesPhoto = false
    @State private var picture: LoadedPicture?
    @State private var pictureFailed = false
    @State private var map: RouteMapImage?
    @State private var selection: String?

    private struct LoadedPicture {
        let image: UIImage
        let isPhoto: Bool
    }

    private struct PictureRequest: Equatable {
        let artworkID: UUID?
        let usesPhoto: Bool
    }

    private var stats: SeriesStats { SeriesStats(series: series) }
    /// The newest encounter unless the user picked another.
    private var cover: Artwork? { series.members.first { $0.id == coverID } ?? series.members.last }

    private var content: SeriesCardContent? {
        guard let picture, let cover else { return nil }
        let stats = stats
        return SeriesCardContent(
            number: (allSeries.firstIndex { $0.id == series.id } ?? 0) + 1,
            title: series.title.trimmingCharacters(in: .whitespaces),
            kind: cover.kind,
            picture: picture.image,
            pictureIsPhoto: picture.isPhoto,
            stats: stats,
            map: map,
            countryOutline: CountryOutlines.shared.outline(for: stats.countryCode))
    }

    var body: some View {
        let options = content.map(SeriesShareCards.options(for:)) ?? []
        ShareCardDeck(phase: pictureFailed ? .failed : (options.isEmpty ? .loading : .ready),
                      options: options,
                      selection: Binding(get: { selection ?? options.first?.id ?? "" }, set: { selection = $0 })) {
            controls
        }
        .task(id: PictureRequest(artworkID: cover?.id, usesPhoto: usesPhoto)) { await loadPicture() }
        // The map's height follows the picture's shape, so a cover of another shape asks again.
        .task(id: picture.map { SeriesShareCard.mapSize(for: $0.image, isPhoto: $0.isPhoto) }) { await loadMap() }
        .onDisappear { context.saveReportingErrors("SeriesShare.rename") }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            TextField("Name this series", text: $series.title)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(series.members.reversed()) { artwork in
                        Button { coverID = artwork.id } label: {
                            ArtworkImageView(artwork: artwork, variant: .thumbnail)
                                .padding(4)
                                .frame(width: 48, height: 48)
                                .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(artwork.id == cover?.id ? Theme.accent : Theme.rule, lineWidth: artwork.id == cover?.id ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(artwork.placeName ?? String(localized: "Unknown place")))
                        .accessibilityAddTraits(artwork.id == cover?.id ? .isSelected : [])
                    }
                }
            }
            Toggle("Use original photo", isOn: $usesPhoto).tint(Theme.accent)
        }
        .padding(.horizontal, 20)
    }

    private func loadPicture() async {
        guard let cover else { pictureFailed = true; return }
        let id = cover.id, cutoutID = cover.cutoutImageID, photoID = cover.originalImageID, wantsPhoto = usesPhoto
        // Cards render at 1080 px wide; 1600 px leaves headroom without decoding huge images.
        let loaded = await Task.detached { () -> (CGImage, Bool)? in
            if wantsPhoto, let photo = ImageStore.shared.loadImage(artworkID: id, imageID: photoID, maxPixelSize: 1600) { return (photo, true) }
            // The original can be missing; the cutout is what the collection shows, so fall back to it.
            return ImageStore.shared.loadImage(artworkID: id, imageID: cutoutID, maxPixelSize: 1600).map { ($0, false) }
        }.value
        guard !Task.isCancelled else { return }
        guard let loaded else { pictureFailed = picture == nil; return }
        picture = LoadedPicture(image: UIImage(cgImage: loaded.0), isPhoto: loaded.1)
    }

    private func loadMap() async {
        guard let picture else { return }
        let size = SeriesShareCard.mapSize(for: picture.image, isPhoto: picture.isPhoto)
        guard map?.size != size else { return }
        let loaded = await RouteMapSnapshotter.snapshot(coordinates: stats.stops.map(\.coordinate), size: size)
        guard !Task.isCancelled else { return }
        // Keep a map of the old size rather than none when the new one can't be loaded.
        if loaded != nil || map == nil { map = loaded }
    }
}
