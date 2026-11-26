import SwiftUI

/// Every piece behind one pin, or in one area, as a grid of cutouts: the way to pick one when
/// there are too many to swipe through in the strip (spec: explore-map).
struct WorldPostGrid: View {
    let scope: WorldStripScope
    let posts: [ExplorePost]
    /// More pieces are on their way from the server.
    let isLoading: Bool
    let config: OnlineConfig
    let state: OnlineState?
    /// A piece was opened, so the strip underneath can end up on the same one.
    let onOpen: (ExplorePost) -> Void

    @State private var opened: ExplorePost?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(scope.title).font(.headline).foregroundStyle(Theme.ink)
                .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 12)
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(posts) { post in
                        Button {
                            onOpen(post)
                            opened = post
                        } label: {
                            WorldPostTile(post: post, config: config)
                        }
                        .buttonStyle(.plain)
                    }
                    if isLoading {
                        ForEach(0..<pendingCount, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rule).aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding(.horizontal, 14)
                if !isLoading, missingCount > 0 {
                    Text("Showing the newest \(posts.count)")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 14)
                }
                Color.clear.frame(height: 20)
            }
        }
        .background(Theme.paperElevated)
        // The piece opens over the grid, so closing it comes back to the same place in the grid.
        .sheet(item: $opened) { post in
            RemotePostSheet(post: post, config: config, state: state)
                .presentationDetents([.medium, .large])
        }
    }

    private var total: Int {
        if case .group(_, let total) = scope { return total }
        return posts.count
    }

    private var missingCount: Int { max(0, total - posts.count) }
    /// Stand-ins for what is still loading, no more than the server will send.
    private var pendingCount: Int { max(0, min(total, WorldFeed.limit) - posts.count) }
}

/// One cutout in the grid.
struct WorldPostTile: View {
    let post: ExplorePost
    let config: OnlineConfig

    var body: some View {
        // The tile is square whatever the cutout's shape, so the rows stay even.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { RemoteImageView(url: post.thumbKey.map(config.imageURL)).padding(7) }
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(Text([post.areaText, post.foundOnText].compactMap { $0 }.joined(separator: ", ")))
    }
}
