import SwiftData
import SwiftUI

/// The one line under the map's title: at most one message at a time, the pointer to the user's
/// own area giving way to anything more pressing.
struct WorldTopNotice: View {
    enum Content: Equatable {
        case notice(String)
        case error(String)
        case pointer(OwnAreaPrompts.Pointer)
    }

    let content: Content
    let onRetry: () -> Void
    let onPointer: () -> Void
    let onDismissPointer: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch content {
            case .notice(let text):
                Image(systemName: "megaphone.fill").foregroundStyle(Theme.accent)
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
            case .error(let text):
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
                Button("Try again", action: onRetry).fontWeight(.semibold).buttonStyle(.plain).foregroundStyle(Theme.accent)
            case .pointer(let pointer):
                Button(action: onPointer) {
                    HStack(spacing: 6) {
                        Text(Self.text(for: pointer)).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onDismissPointer) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSecondary).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink)
        .lineLimit(2)
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    static func text(for pointer: OwnAreaPrompts.Pointer) -> String {
        if let place = pointer.placeName {
            return String(localized: "\(place): your \(pointer.pieceCount) pieces would be the first public ones there")
        }
        return String(localized: "Your \(pointer.pieceCount) pieces would be the first public ones where you found them")
    }
}

/// What the strip shows where the map has no public pieces: an invitation built from the user's
/// own pieces here when there are some, and otherwise only a way back to where pieces are.
struct WorldEmptyArea: View {
    let invitation: OwnAreaPrompts.Invitation?
    /// The user's pieces the invitation shows, newest first.
    let pieces: [Artwork]
    let hasPiecesElsewhere: Bool
    let onShare: () -> Void
    let onDismiss: () -> Void
    let onNearest: () -> Void

    var body: some View {
        // No taller than the strip it stands in for: the map keeps that much clear, and anything
        // higher would cover the map's own mark.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("No public pieces here yet.").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if hasPiecesElsewhere {
                    Button("Nearest pieces", action: onNearest)
                        .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.accent).lineLimit(1)
                }
                if invitation != nil {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSecondary)
                            .frame(width: 28, height: 28).background(Theme.rule, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss"))
                }
            }
            switch invitation {
            case .share(let ids):
                HStack(spacing: 12) {
                    HStack(spacing: -14) {
                        ForEach(pieces.prefix(3)) { artwork in
                            ArtworkImageView(artwork: artwork, variant: .thumbnail)
                                .padding(4).frame(width: 46, height: 46)
                                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You found \(ids.count) pieces around here").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Button(action: onShare) {
                            Text("Be the first to share one").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            case .inReview(let count):
                Text("Your \(count) pieces here are in review").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

/// Pick which of one's pieces in an area to make public; the choice opens the usual publish sheet.
struct OwnPiecesPicker: View {
    let pieces: [Artwork]
    let onSelect: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(pieces) { artwork in
                        Button { onSelect(artwork) } label: { StickerCard(artwork: artwork) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(PaperBackground())
            .navigationTitle("Choose a piece to share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
