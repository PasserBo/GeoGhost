import SwiftUI

/// Pick a card style, preview it, and hand the rendered PNG to the system share sheet.
struct ShareCardSheet: View {
    let artwork: Artwork

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var content: ShareCardContent?
    @State private var style: ShareCardStyle = .fieldNote
    @State private var showsCredit = true
    @State private var showPaywall = false
    @State private var exportItem: ExportItem?
    @State private var loadFailed = false
    @State private var renderFailed = false

    private var isPro: Bool { services.pro.isPro }
    /// With purchasing off (v1.0), Pro styles and the credit toggle are hidden rather than shown locked.
    private var styles: [ShareCardStyle] { services.pro.showsProFeatures ? ShareCardStyle.allCases : ShareCardStyle.allCases.filter { !$0.isPro } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                preview
                if styles.count > 1 { stylePicker }
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
                Spacer(minLength: 0)
                Button { share() } label: { Label("Share card", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(content == nil)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
            .background(PaperBackground())
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(item: $exportItem) { item in ShareSheet(items: [item.url]) }
            .alert("Couldn't create the card", isPresented: $renderFailed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Something went wrong while drawing the card. Please try again.") }
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / ShareCardView.size.width, geo.size.height / ShareCardView.size.height)
            ZStack {
                if loadFailed {
                    EmptyStateView(systemImage: "photo.badge.exclamationmark", title: "Couldn't load this piece",
                                   message: "Its image file is missing or damaged.")
                } else if let content {
                    ShareCardView(content: content, style: style, showsCredit: showsCredit || !isPro)
                        .clipShape(RoundedRectangle(cornerRadius: 8 / scale, style: .continuous))
                        .scaleEffect(scale)
                        .frame(width: ShareCardView.size.width * scale, height: ShareCardView.size.height * scale)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(styles) { s in
                    Button {
                        if s.isPro && !isPro { showPaywall = true } else { style = s }
                    } label: {
                        HStack(spacing: 5) {
                            Text(s.title).font(.subheadline.weight(.semibold))
                            if s.isPro && !isPro { Image(systemName: "lock.fill").font(.caption2) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(style == s ? Theme.accent : Theme.paperElevated, in: Capsule())
                        .foregroundStyle(style == s ? .white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func load() async {
        let id = artwork.id, imageID = artwork.cutoutImageID
        // Cards render at 1080 px wide; 1600 px leaves headroom for the sticker without decoding huge cutouts.
        let image = await Task.detached { ImageStore.shared.loadImage(artworkID: id, imageID: imageID, maxPixelSize: 1600) }.value
        guard let image else { loadFailed = true; return }
        content = ShareCardContent(artwork: artwork, sticker: UIImage(cgImage: image))
    }

    private func share() {
        guard let content else { return }
        if let url = ShareCardView.renderPNG(content: content, style: style, showsCredit: showsCredit || !isPro) {
            exportItem = ExportItem(url: url)
        } else {
            renderFailed = true
        }
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
