import MapKit
import SwiftUI

/// What the strip under the world map is showing.
enum WorldStripScope: Equatable {
    /// The newest public pieces anywhere.
    case latest
    /// The pieces behind one pin.
    case group(id: UUID, total: Int)
    /// The pieces in the part of the map that was on screen when the user asked for it.
    case area
}

/// The strip of cards under the world map. The card in front is the piece marked on the map, so
/// the list and the map never disagree about what is selected.
struct WorldStrip: View {
    let scope: WorldStripScope
    let posts: [ExplorePost]
    let isLoading: Bool
    let config: OnlineConfig
    /// The user moved the map away from what the strip lists, so it can offer to list what is there.
    let offersThisArea: Bool
    @Binding var focusedID: UUID?
    let onOpen: (ExplorePost) -> Void
    let onBackToLatest: () -> Void
    let onThisArea: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                switch scope {
                case .latest:
                    if offersThisArea { headerButton("Only this area", action: onThisArea) }
                case .group(_, let total):
                    if total > 1 { headerButton("Zoom in here", action: onZoomIn) }
                    closeButton
                case .area:
                    closeButton
                }
            }
            .padding(.horizontal, 14)
            if posts.isEmpty, isLoading {
                placeholders
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(posts) { post in
                            Button { onOpen(post) } label: { WorldPostCard(post: post, config: config, isFocused: post.id == focusedID) }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal) { width, _ in max(200, width - 72) }
                                .id(post.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedID, anchor: .leading)
                .contentMargins(.horizontal, 14, for: .scrollContent)
                // A horizontal scroll view takes all the height it is offered.
                .frame(height: WorldPostCard.height)
            }
        }
        .padding(.vertical, 12)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    private var title: LocalizedStringKey {
        switch scope {
        case .latest: "Latest finds"
        case .group(_, let total): "\(total) pieces here"
        case .area: "In this area"
        }
    }

    private func headerButton(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.footnote.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
    }

    private var closeButton: some View {
        Button(action: onBackToLatest) {
            Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.rule, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back to latest finds"))
    }

    /// Stand-ins while the first load is in flight, the size of real cards so nothing jumps.
    private var placeholders: some View {
        HStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.rule).frame(height: WorldPostCard.height)
            }
        }
        .padding(.horizontal, 14)
        .accessibilityLabel(Text("Loading"))
    }
}

/// One public piece in the strip: the cutout and what was published with it.
struct WorldPostCard: View {
    static let height: CGFloat = 72

    let post: ExplorePost
    let config: OnlineConfig
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: post.thumbKey.map(config.imageURL))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.areaText).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isFocused ? Theme.accent : Theme.rule, lineWidth: isFocused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var detail: String {
        [post.foundOnText, post.authorNickname].compactMap { $0 }.joined(separator: " · ")
    }
}

extension ExplorePost {
    /// "杉並区, Japan": as much of the place as was published.
    var areaText: String {
        let country = countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        let parts = [locality, country].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Unknown area") : parts.joined(separator: ", ")
    }

    /// The server's calendar day, shown as that same day whatever the phone's time zone.
    var foundOnText: String? {
        guard let capturedOn else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = capturedOn.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return capturedOn }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

// MARK: - Pins

/// A piece without a thumbnail: more pieces are in view than the map has room to show in full.
struct WorldDotPin: View {
    let kind: ArtworkKind
    let isSelected: Bool

    var body: some View {
        Circle().fill(kind.tint)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: isSelected ? 18 : 13, height: isSelected ? 18 : 13)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            // Larger than it looks, so a finger can hit it.
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
}

/// A piece, or the newest of several in one spot with how many there are.
struct WorldGroupPin: View {
    let group: WorldPinLayout.Group
    let config: OnlineConfig
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ExplorePostPin(post: group.representative, config: config, size: isSelected ? 56 : 46)
                .overlay {
                    if isSelected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent, lineWidth: 3) }
                }
            if group.count > 1 {
                Text("\(group.count)")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: 8, y: -8)
            }
        }
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}
