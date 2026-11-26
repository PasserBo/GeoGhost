import SwiftUI

/// A field-guide entry for one series: its number, a big picture, one number that leads, a map of
/// where it was seen and the remaining figures in small print.
struct SeriesShareCard: View {
    /// Which number the card leads with.
    enum Lead: String, CaseIterable, Sendable { case distance, encounters }

    /// How the card arranges itself around its picture. A cutout keeps its own shape, and one
    /// that is far from square would otherwise sit small in a box made for square ones.
    enum Arrangement: Equatable, Sendable {
        /// Picture on top, text below.
        case stacked
        /// A tall picture down the left side with the text beside it.
        case sideBySide
    }

    private static let padding: CGFloat = 20
    private static let contentWidth = ShareCardLayout.size.width - padding * 2
    private static let regularMapHeight: CGFloat = 112
    private static let tallestMapHeight: CGFloat = 176
    /// About what the stacked arrangement leaves for the picture above a regular map.
    private static let stackedPictureHeight: CGFloat = 150
    /// About what the side-by-side arrangement leaves beside the text, above a regular map.
    private static let sidePictureHeight: CGFloat = 214
    /// Narrower than this (width ÷ height) and the picture goes down the side.
    private static let tallAspect: CGFloat = 0.7

    /// Width ÷ height of a cutout; nil for a photo, which fills whatever box it gets.
    private static func cutoutAspect(_ picture: UIImage, isPhoto: Bool) -> CGFloat? {
        guard !isPhoto, picture.size.width > 0, picture.size.height > 0 else { return nil }
        return picture.size.width / picture.size.height
    }

    static func arrangement(for picture: UIImage, isPhoto: Bool) -> Arrangement {
        guard let aspect = cutoutAspect(picture, isPhoto: isPhoto) else { return .stacked }
        return aspect < tallAspect ? .sideBySide : .stacked
    }

    /// The size to request the map at. A wide cutout doesn't need the height a square one does, so
    /// the map takes it. The height moves in steps so near-identical pictures share a map.
    static func mapSize(for picture: UIImage, isPhoto: Bool) -> CGSize {
        var height = regularMapHeight
        if let aspect = cutoutAspect(picture, isPhoto: isPhoto), aspect > 1 {
            let spare = stackedPictureHeight - contentWidth / aspect
            if spare > 0 { height = min(tallestMapHeight, regularMapHeight + (spare / 8).rounded(.down) * 8) }
        }
        return CGSize(width: contentWidth, height: height)
    }

    let content: SeriesCardContent
    let lead: Lead

    private var arrangement: Arrangement { Self.arrangement(for: content.picture, isPhoto: content.pictureIsPhoto) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "No. " + String(format: "%03d", content.number))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ShareCardPalette.inkSecondary)
                Spacer()
                KindChip(kind: content.kind)
            }
            switch arrangement {
            case .stacked:
                picture.padding(.vertical, 12)
                title
                headline.padding(.top, 2)
            case .sideBySide:
                HStack(alignment: .center, spacing: 18) {
                    picture.frame(width: sidePictureWidth)
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        Text(leading).font(.display(26)).foregroundStyle(Theme.accent).lineLimit(2).minimumScaleFactor(0.7)
                        if let trailing {
                            Text(verbatim: trailing).font(.system(size: 13, weight: .medium)).foregroundStyle(ShareCardPalette.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            if let map = content.map {
                SeriesRouteMapView(map: map, stats: content.stats, locator: content.locator)
                    .frame(width: map.size.width, height: map.size.height)
                    .padding(.top, 10)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(figures).font(.system(size: 11)).foregroundStyle(ShareCardPalette.inkSecondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                ShareCardCredit()
            }
            .padding(.top, 10)
        }
        .foregroundStyle(ShareCardPalette.ink)
        .padding(Self.padding)
        .frame(width: ShareCardLayout.size.width, height: ShareCardLayout.size.height)
        .background(ShareCardPalette.paper)
        .environment(\.colorScheme, .light)
    }

    /// As wide as the picture comes out at the height there is, within sensible limits.
    private var sidePictureWidth: CGFloat {
        let aspect = Self.cutoutAspect(content.picture, isPhoto: content.pictureIsPhoto) ?? 1
        // Without a map the block above the footer is taller by the map's height and its gap.
        let height = Self.sidePictureHeight + (content.map == nil ? Self.regularMapHeight + 10 : 0)
        return min(150, max(56, height * aspect))
    }

    @ViewBuilder private var title: some View {
        if !content.title.isEmpty {
            Text(content.title).font(.display(19)).lineLimit(arrangement == .sideBySide ? 2 : 1)
        }
    }

    @ViewBuilder private var picture: some View {
        if content.pictureIsPhoto {
            Color.clear
                .overlay { Image(uiImage: content.picture).resizable().interpolation(.high).scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(uiImage: content.picture)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
        }
    }

    /// The leading number in large type, with the other measure beside it in small type.
    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(leading).font(.display(28)).foregroundStyle(Theme.accent)
            if let trailing {
                Text(verbatim: "· " + trailing).font(.system(size: 13, weight: .medium)).foregroundStyle(ShareCardPalette.inkSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var leading: String {
        if lead == .distance, let meters = content.stats.distanceMeters {
            return String(localized: "\(DistanceText.metric(meters)) apart")
        }
        return String(localized: "Seen \(content.stats.encounterCount)×")
    }

    private var trailing: String? {
        guard let meters = content.stats.distanceMeters else { return nil }
        if lead == .distance { return DistanceText.imperial(meters) }
        return String(localized: "within \(DistanceText.metric(meters))")
    }

    private var figures: String {
        var parts = [String(localized: "\(content.stats.encounterCount) encounters")]
        if content.stats.placeCount > 0 { parts.append(String(localized: "\(content.stats.placeCount) places")) }
        if let days = content.stats.spanDays() { parts.append(String(localized: "\(days) days")) }
        return parts.joined(separator: " · ")
    }
}
