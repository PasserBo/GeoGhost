import SwiftUI

/// A field-guide entry for one series: its number, a big picture, one number that leads, a map of
/// where it was seen and the remaining figures in small print.
struct SeriesShareCard: View {
    /// Which number the card leads with.
    enum Lead: String, CaseIterable, Sendable { case distance, encounters }

    static let mapHeight: CGFloat = 112
    private static let padding: CGFloat = 20
    /// The map is as wide as the card's content, so a snapshot of this size fits it exactly.
    static let mapSize = CGSize(width: ShareCardLayout.size.width - padding * 2, height: mapHeight)

    let content: SeriesCardContent
    let lead: Lead

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "No. " + String(format: "%03d", content.number))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ShareCardPalette.inkSecondary)
                Spacer()
                KindChip(kind: content.kind)
            }
            picture.padding(.vertical, 12)
            if !content.title.isEmpty {
                Text(content.title).font(.display(19)).lineLimit(1)
            }
            headline.padding(.top, 2)
            if let map = content.map {
                SeriesRouteMapView(map: map, stats: content.stats, locator: content.locator)
                    .frame(width: Self.mapSize.width, height: Self.mapSize.height)
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
