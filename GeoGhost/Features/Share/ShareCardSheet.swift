import SwiftUI

/// Share one piece: prepares its content and offers each card style as an option of the deck.
struct ShareCardSheet: View {
    let artwork: Artwork

    @Services private var services
    @State private var content: ShareCardContent?
    @State private var selection = ShareCardStyle.fieldNote.rawValue
    @State private var showsCredit = true
    @State private var showPaywall = false
    @State private var loadFailed = false

    private var isPro: Bool { services.pro.isPro }
    /// With purchasing off (v1.0), Pro styles and the credit toggle are hidden rather than shown locked.
    private var styles: [ShareCardStyle] { services.pro.showsProFeatures ? ShareCardStyle.allCases : ShareCardStyle.allCases.filter { !$0.isPro } }

    private var options: [ShareCardOption] {
        guard let content else { return [] }
        let credit = showsCredit || !isPro
        return styles.map { style in
            ShareCardOption(id: style.rawValue, title: style.title, isLocked: style.isPro && !isPro) {
                ShareCardView(content: content, style: style, showsCredit: credit)
            }
        }
    }

    var body: some View {
        ShareCardDeck(phase: loadFailed ? .failed : (content == nil ? .loading : .ready),
                      options: options, selection: $selection, onLocked: { showPaywall = true }) {
            if services.pro.showsProFeatures {
                Toggle(isOn: Binding(get: { showsCredit || !isPro }, set: { newValue in
                    if isPro { showsCredit = newValue } else { showPaywall = true }
                })) {
                    HStack(spacing: 6) {
                        Text("Show GeoGhost credit")
                        if !isPro { ProBadge() }
                    }
                }
                .tint(Theme.accent)
                .padding(.horizontal, 20)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func load() async {
        let id = artwork.id, imageID = artwork.cutoutImageID
        // Cards render at 1080 px wide; 1600 px leaves headroom for the sticker without decoding huge cutouts.
        let image = await Task.detached { ImageStore.shared.loadImage(artworkID: id, imageID: imageID, maxPixelSize: 1600) }.value
        guard let image else { loadFailed = true; return }
        content = ShareCardContent(artwork: artwork, sticker: UIImage(cgImage: image))
    }
}

/// Small "PRO" capsule used next to locked options.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
    }
}
