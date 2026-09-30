import MapKit
import SwiftData
import SwiftUI

struct ArtworkDetailView: View {
    @Bindable var artwork: Artwork
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showOriginal = false
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var exportItem: ExportItem?
    @State private var reopen: CaptureView.StoredPhoto?
    @Query private var siblings: [Artwork]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                header
                if let series = artwork.series, series.encounterCount > 1 { seriesCard(series) }
                metadataCard
                if !artwork.note.isEmpty || !artwork.tagList.isEmpty { notesCard }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { artwork.isFavorite.toggle(); try? context.save() } label: {
                    Image(systemName: artwork.isFavorite ? "heart.fill" : "heart").foregroundStyle(artwork.isFavorite ? .red : Theme.ink)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isEditing = true } label: { Label("Edit details", systemImage: "pencil") }
                    Button { export() } label: { Label("Share sticker", systemImage: "square.and.arrow.up") }
                    Button { reopenPhoto(recut: true) } label: { Label("Edit this piece", systemImage: "scissors") }
                    Button { reopenPhoto() } label: { Label("Add another from this photo", systemImage: "plus.viewfinder") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $isEditing) { EditArtworkSheet(artwork: artwork) }
        .sheet(item: $exportItem) { item in ShareSheet(items: [item.url]) }
        .fullScreenCover(item: Binding(get: { reopen.map { ReopenItem(photo: $0) } }, set: { if $0 == nil { reopen = nil } })) { item in
            CaptureView(stored: item.photo)
        }
        .confirmationDialog("Delete this piece?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: { Text("The cutout and the original photo will be removed from GeoGhost.") }
    }

    private var hero: some View {
        ZStack {
            if showOriginal {
                ArtworkImageView(artwork: artwork, variant: .original)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay {
                        GeometryReader { geo in
                            let r = artwork.cutoutRect
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .frame(width: r.width * geo.size.width, height: r.height * geo.size.height)
                                .position(x: (r.midX) * geo.size.width, y: (r.midY) * geo.size.height)
                        }
                    }
            } else {
                ArtworkImageView(artwork: artwork, variant: .cutout)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 260)
                    .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)) }
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .overlay(alignment: .bottomTrailing) {
            Picker("", selection: $showOriginal) {
                Image(systemName: "seal.fill").tag(false)
                Image(systemName: "photo").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .padding(10)
        }
        .animation(.easeInOut(duration: 0.2), value: showOriginal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                KindChip(kind: artwork.kind)
                if artwork.segmentationMode == .manualCrop { Text("Hand crop").font(.caption).foregroundStyle(Theme.inkSecondary) }
                Spacer()
            }
            Text(artwork.placeName ?? String(localized: "Unknown place")).font(.display(24))
            Text(artwork.displayDate.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seriesCard(_ series: ArtSeries) -> some View {
        NavigationLink { SeriesDetailView(series: series) } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seen \(series.encounterCount) times").font(.headline)
                    Text(series.distinctLocalities.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                HStack(spacing: -10) {
                    ForEach(series.members.filter { $0.id != artwork.id }.prefix(3)) { a in
                        ArtworkImageView(artwork: a, variant: .thumbnail).frame(width: 40, height: 40)
                    }
                }
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSecondary)
            }
            .padding(14)
            .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            if let c = artwork.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 400, longitudinalMeters: 400)), interactionModes: []) {
                    Annotation("", coordinate: c) { ArtworkPin(artwork: artwork) }
                }
                .frame(height: 160)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cornerRadius, topTrailingRadius: Theme.cornerRadius))
                .overlay(alignment: .topTrailing) {
                    Button { openInMaps(c) } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").padding(8).background(.ultraThinMaterial, in: Circle())
                    }.padding(8)
                }
            }
            VStack(spacing: 0) {
                if let c = artwork.coordinate {
                    metaRow("Coordinates", String(format: "%.5f, %.5f", c.latitude, c.longitude), mono: true)
                    if let acc = artwork.horizontalAccuracy { metaRow("Accuracy", "±\(Int(acc)) m") }
                    if let h = artwork.heading { metaRow("Facing", "\(Int(h))° \(compass(h))") }
                    metaRow("Location source", sourceLabel(artwork.locationSource))
                } else {
                    metaRow("Location", String(localized: "Not recorded"))
                }
                if artwork.capturedAtIsEstimated { metaRow("Time", String(localized: "Import time (no EXIF date)")) }
                if let d = artwork.deviceModel { metaRow("Device", d) }
                if let l = artwork.lensModel { metaRow("Lens", l) }
                if artwork.imagePixelWidth > 0 { metaRow("Original", "\(artwork.imagePixelWidth) × \(artwork.imagePixelHeight)") }
                if let hex = artwork.dominantColorHex, let ui = UIColor(hex: hex) {
                    HStack {
                        Text("Dominant color").foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Circle().fill(Color(uiColor: ui)).frame(width: 16, height: 16)
                        Text(hex).monospaced()
                    }
                    .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !artwork.note.isEmpty { Text(artwork.note).font(.body) }
            if !artwork.tagList.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(artwork.tagList, id: \.name) { t in
                        Text("#\(t.name)").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.rule, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func metaRow(_ label: LocalizedStringResource, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value).monospacedDigit().font(mono ? .subheadline.monospaced() : .subheadline)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func sourceLabel(_ s: LocationSource) -> String {
        switch s {
        case .device: String(localized: "Device GPS")
        case .exif: String(localized: "Photo metadata")
        case .manual: String(localized: "Set by hand")
        case .none: String(localized: "None")
        }
    }

    private func compass(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((deg + 22.5) / 45) % 8]
    }

    private func openInMaps(_ c: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = artwork.placeName ?? "GeoGhost"
        item.openInMaps()
    }

    private func export() {
        let id = artwork.id, imageID = artwork.cutoutImageID
        let name = "GeoGhost-\(artwork.kind.rawValue)-\(artwork.displayDate.formatted(.iso8601.year().month().day())).png"
        Task.detached {
            guard let data = ImageStore.shared.loadData(artworkID: id, imageID: imageID) else { return }
            let url = FileManager.default.temporaryDirectory.appending(path: name)
            try? data.write(to: url)
            await MainActor.run { exportItem = ExportItem(url: url) }
        }
    }

    /// Reopen the original photo in the picker; pieces already saved from it (by pixel size + capture time) are ghosted.
    /// `recut` = re-select this same piece (its own region is not ghosted; the result replaces it).
    private func reopenPhoto(recut: Bool = false) {
        let id = artwork.id, imageID = artwork.originalImageID
        let metadata = artwork.captureMetadata
        let sameShot = siblings.filter { $0.capturedAt == artwork.capturedAt && $0.imagePixelWidth == artwork.imagePixelWidth && $0.imagePixelHeight == artwork.imagePixelHeight }
        let saved = sameShot.filter { !recut || $0.id != id }.map(\.cutoutRect)
        // Load off the main thread, then build the (main-actor-bound) StoredPhoto back on it.
        Task {
            let data = await Task.detached { ImageStore.shared.loadData(artworkID: id, imageID: imageID) }.value
            guard let data else { return }
            reopen = CaptureView.StoredPhoto(data: data, metadata: metadata, savedRegions: saved, replacing: recut ? artwork : nil)
        }
    }

    private func delete() {
        let id = artwork.id
        let series = artwork.series
        context.delete(artwork)
        if let series, (series.artworks?.count ?? 0) <= 1 { context.delete(series) }
        try? context.save()
        Task { await ImageStore.shared.delete(artworkID: id) }
        dismiss()
    }
}

struct ExportItem: Identifiable { let id = UUID(); let url: URL }
private struct ReopenItem: Identifiable { let id = UUID(); let photo: CaptureView.StoredPhoto }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Map pin: the sticker itself in a small paper frame.
struct ArtworkPin: View {
    let artwork: Artwork
    var size: CGFloat = 44
    var body: some View {
        ArtworkImageView(artwork: artwork, variant: .thumbnail)
            .padding(4)
            .frame(width: size, height: size)
            .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(artwork.kind.tint, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

/// Minimal wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
