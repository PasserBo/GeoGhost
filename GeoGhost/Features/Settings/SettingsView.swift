import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query private var artworks: [Artwork]
    @State private var storageBytes: Int64 = 0
    @State private var confirmWipe = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @AppStorage("seriesStrictness") private var strictness: Double = 0.55

    var body: some View {
        NavigationStack {
            List {
                proSection
                Section("Series matching") {
                    VStack(alignment: .leading) {
                        HStack { Text("Strictness"); Spacer(); Text(strictness < 0.5 ? "Strict" : strictness > 0.6 ? "Loose" : "Balanced").foregroundStyle(Theme.inkSecondary) }
                        Slider(value: $strictness, in: 0.4...0.7, step: 0.05) { Text("Strictness") }
                            .onChange(of: strictness) { _, v in SeriesAssigner.matcher.matchThreshold = Float(v); SeriesAssigner.matcher.suggestionThreshold = Float(v) + 0.2 }
                        Text("Lower is stricter: fewer false links between different designs.").font(.caption).foregroundStyle(Theme.inkSecondary)
                    }
                    Button("Re-run matching for unlinked pieces") { Task { await SeriesAssigner.rematchAll(in: context) } }
                }
                Section("Data") {
                    LabeledContent("Pieces", value: "\(artworks.count)")
                    LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                    Button { export() } label: { HStack { Text("Export everything (ZIP)"); if isExporting { Spacer(); ProgressView() } } }.disabled(isExporting || artworks.isEmpty)
                    Button("Delete all data", role: .destructive) { confirmWipe = true }.disabled(artworks.isEmpty)
                }
                Section("Privacy") {
                    Text("Photos, cutouts and locations stay on this device. Subject detection, matching and classification run entirely on-device.")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("Camera & location permissions", destination: url) }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Link("Privacy policy", destination: URL(string: "https://passerbo.github.io/GeoGhost/privacy/")!)
                    Link("Support", destination: URL(string: "https://passerbo.github.io/GeoGhost/support/")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            
            .navigationTitle("Settings")
            .task { storageBytes = await ImageStore.shared.totalSize() }
            .onAppear { SeriesAssigner.matcher.matchThreshold = Float(strictness) }
            .confirmationDialog("Delete all pieces?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { wipe() }
            } message: { Text("This removes every piece, photo and series from GeoGhost on this device. It cannot be undone.") }
            .sheet(item: Binding(get: { exportURL.map { ExportItem(url: $0) } }, set: { _ in exportURL = nil })) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    @ViewBuilder private var proSection: some View {
        let pro = services.pro
        Section {
            if pro.isPro {
                Label { Text("GeoGhost Pro is active").fontWeight(.semibold) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GeoGhost Pro").font(.display(20))
                    Text("Unlimited pieces (free: \(ProStore.freeLimit)), high-resolution exports, and everything that comes next. One-time purchase.")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    Button {
                        Task { await pro.purchase() }
                    } label: {
                        Text(pro.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock Pro")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(pro.isLoading)
                }
                .padding(.vertical, 6)
                Button("Restore purchase") { Task { await pro.restore() } }
                if let e = pro.lastError { Text(e).font(.caption).foregroundStyle(.red) }
            }
        } header: { Text("Pro") } footer: { Text("\(artworks.count) of \(pro.isPro ? "∞" : "\(ProStore.freeLimit)") pieces used.") }
    }

    private func wipe() {
        for a in artworks { context.delete(a) }
        for s in (try? context.fetch(FetchDescriptor<ArtSeries>())) ?? [] { context.delete(s) }
        for t in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] { context.delete(t) }
        try? context.save()
        ImageCache.shared.remove(prefix: "")
        Task { try? await ImageStore.shared.deleteAll(); storageBytes = 0 }
    }

    private func export() {
        isExporting = true
        let manifest = artworks.map(ExportRecord.init)
        Task.detached(priority: .userInitiated) {
            let url = try? DataExporter.exportAll(records: manifest)
            await MainActor.run { exportURL = url; isExporting = false }
        }
    }
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
