import SwiftUI

/// The body of every share sheet: swipe between the cards on offer, then hand the one on screen
/// to the system share sheet as a PNG. What the cards are, and any controls that change them,
/// come from the sheet that owns the deck.
struct ShareCardDeck<Controls: View>: View {
    enum Phase { case loading, failed, ready }

    let phase: Phase
    let options: [ShareCardOption]
    @Binding var selection: String
    /// The user tried to share a locked card.
    var onLocked: () -> Void = {}
    @ViewBuilder var controls: Controls

    @Environment(\.dismiss) private var dismiss
    @State private var exportItem: ExportItem?
    @State private var renderFailed = false

    private var current: ShareCardOption? { options.first { $0.id == selection } ?? options.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                if phase == .ready, options.count > 1 { pageIndicator }
                controls
                Button { share() } label: {
                    Label("Share card", systemImage: current?.isLocked == true ? "lock.fill" : "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(phase != .ready || current == nil)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
            .background(PaperBackground())
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $exportItem) { item in ShareSheet(items: [item.url]) }
            .alert("Couldn't create the card", isPresented: $renderFailed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Something went wrong while drawing the card. Please try again.") }
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let size = ShareCardLayout.size
            // Leave room at the sides so the neighbouring card doesn't touch the edge while swiping.
            let scale = max(0.1, min((geo.size.width - 64) / size.width, geo.size.height / size.height))
            ZStack {
                switch phase {
                case .failed:
                    EmptyStateView(systemImage: "photo.badge.exclamationmark", title: "Couldn't load this piece",
                                   message: "Its image file is missing or damaged.")
                case .loading:
                    ProgressView()
                case .ready:
                    TabView(selection: $selection) {
                        ForEach(options) { option in
                            option.card()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .environment(\.colorScheme, .light)
                                .clipShape(RoundedRectangle(cornerRadius: 8 / scale, style: .continuous))
                                .scaleEffect(scale)
                                .frame(width: size.width * scale, height: size.height * scale)
                                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                                .tag(option.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pageIndicator: some View {
        VStack(spacing: 6) {
            if let current {
                HStack(spacing: 5) {
                    Text(current.title).font(.subheadline.weight(.semibold))
                    if current.isLocked { Image(systemName: "lock.fill").font(.caption2) }
                }
                .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 6) {
                ForEach(options) { option in
                    Circle()
                        .fill(option.id == current?.id ? Theme.accent : Theme.ink.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func share() {
        guard let current else { return }
        if current.isLocked { onLocked(); return }
        if let url = ShareCardRenderer.renderPNG(current) {
            exportItem = ExportItem(url: url)
        } else {
            renderFailed = true
        }
    }
}
