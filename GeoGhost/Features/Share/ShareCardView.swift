import SwiftUI
import UIKit

/// Visual styles for the share card. `fieldNote` is free; the rest need Pro.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case fieldNote, polaroid, poster, minimal

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .fieldNote: "Field note"
        case .polaroid: "Polaroid"
        case .poster: "Poster"
        case .minimal: "Minimal"
        }
    }

    var isPro: Bool { self != .fieldNote }
}

/// Everything the card shows, captured up front so rendering doesn't touch SwiftData.
struct ShareCardContent {
    let sticker: UIImage
    let kind: ArtworkKind
    let place: String
    let region: String?
    let date: Date
    let encounters: Int
    let tint: Color

    @MainActor init(artwork: Artwork, sticker: UIImage) {
        self.sticker = sticker
        kind = artwork.kind
        place = artwork.placeName ?? String(localized: "Somewhere on the street")
        region = [artwork.localityName, artwork.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }]
            .compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        date = artwork.displayDate
        encounters = artwork.series?.encounterCount ?? 1
        tint = artwork.dominantColorHex.flatMap(UIColor.init(hex:)).map(Color.init(uiColor:)) ?? Theme.accent
    }
}

/// A 4:5 card (1080×1350 at render scale) laid out in points at 360×450.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    let content: ShareCardContent
    let style: ShareCardStyle
    let showsCredit: Bool

    var body: some View {
        Group {
            switch style {
            case .fieldNote: fieldNote
            case .polaroid: polaroid
            case .poster: poster
            case .minimal: minimal
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    // MARK: Styles

    private var fieldNote: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                KindChip(kind: content.kind)
                Spacer()
                if content.encounters > 1 { Text("Seen \(content.encounters)×").font(.caption.weight(.bold)).foregroundStyle(Theme.accent) }
            }
            sticker.padding(.vertical, 18)
            Rectangle().fill(Self.ink.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.place).font(.display(20)).lineLimit(2)
                if let r = content.region { Text(r).font(.footnote).foregroundStyle(Self.inkSecondary) }
                Text(content.date.formatted(date: .long, time: .omitted)).font(.footnote.monospacedDigit()).foregroundStyle(Self.inkSecondary)
            }
            .padding(.top, 12)
            if showsCredit { credit.padding(.top, 10) }
        }
        .foregroundStyle(Self.ink)
        .padding(24)
        .background(Self.paper)
    }

    private var polaroid: some View {
        VStack(spacing: 14) {
            sticker
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(content.tint.opacity(0.18))
            VStack(spacing: 2) {
                Text(content.place).font(.system(size: 19, weight: .medium, design: .serif).italic()).lineLimit(1)
                Text(content.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Self.inkSecondary)
            }
            if showsCredit { credit } else { Spacer().frame(height: 4) }
        }
        .foregroundStyle(Self.ink)
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 14, trailing: 20))
        .background(.white)
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            content.tint
            Color.black.opacity(0.4)   // the tint is the sticker's own color; darken it so the sticker stands out
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            sticker
                .padding(36)
                .padding(.bottom, 70)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.place.uppercased()).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(2)
                Text([content.region, content.date.formatted(.dateTime.year().month())].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold)).opacity(0.85)
                if showsCredit { credit.padding(.top, 6) }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
    }

    private var minimal: some View {
        ZStack(alignment: .bottom) {
            Self.paper
            sticker.padding(44)
            if showsCredit { credit.foregroundStyle(Self.inkSecondary).padding(.bottom, 16) }
        }
    }

    // MARK: Parts

    private var sticker: some View {
        Image(uiImage: content.sticker)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .black.opacity(style == .poster ? 0 : 0.18), radius: 6, y: 4)
    }

    private var credit: some View {
        HStack(spacing: 4) {
            Image(systemName: "seal.fill").font(.system(size: 9))
            Text("GeoGhost").font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .opacity(0.7)
    }

    // Fixed light palette so cards look the same whatever the device appearance.
    private static let paper = Color(red: 0.965, green: 0.945, blue: 0.905)
    private static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    private static let inkSecondary = Color(red: 0.42, green: 0.40, blue: 0.37)
}

extension ShareCardView {
    /// Renders the card to a 1080×1350 PNG in the temporary directory.
    @MainActor static func renderPNG(content: ShareCardContent, style: ShareCardStyle, showsCredit: Bool) -> URL? {
        let renderer = ImageRenderer(content: ShareCardView(content: content, style: style, showsCredit: showsCredit))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "GeoGhost-card-\(style.rawValue).png")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
