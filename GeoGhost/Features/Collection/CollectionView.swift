import SwiftData
import SwiftUI

/// The sticker album: every collected piece as a transparent cutout on paper.
struct CollectionView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, kind, place
        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .newest: "Newest first"
            case .oldest: "Oldest first"
            case .kind: "By type"
            case .place: "By place"
            }
        }
    }

    @Query(sort: \Artwork.createdAt, order: .reverse) private var artworks: [Artwork]
    @State private var searchText = ""
    @State private var sort: Sort = .newest
    @State private var kindFilter: ArtworkKind?
    @State private var favoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 10)]

    var body: some View {
        NavigationStack {
            Group {
                if artworks.isEmpty {
                    EmptyStateView(systemImage: "seal", title: "Your field guide is empty",
                                   message: "Tap the camera to collect the first sticker, graffiti or mural you spot on the street.")
                } else {
                    grid
                }
            }
            .background(PaperBackground())
            .navigationTitle("Collection")
            .searchable(text: $searchText, prompt: "Search notes, tags, places")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.title).tag($0) } }
                        Divider()
                        Toggle(isOn: $favoritesOnly) { Label("Favorites only", systemImage: "heart") }
                        Menu("Type") {
                            Button("All types") { kindFilter = nil }
                            ForEach(ArtworkKind.allCases) { k in Button { kindFilter = k } label: { Label(k.title, systemImage: k.symbolName) } }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
        }
    }

    private var filtered: [Artwork] {
        var items = artworks
        if let kindFilter { items = items.filter { $0.kind == kindFilter } }
        if favoritesOnly { items = items.filter(\.isFavorite) }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter { a in
                a.note.lowercased().contains(q) || (a.placeName?.lowercased().contains(q) ?? false)
                    || a.tagList.contains { $0.name.contains(q) } || a.kind.rawValue.contains(q)
                    || (a.series?.title.lowercased().contains(q) ?? false)
            }
        }
        switch sort {
        case .newest: items.sort { $0.displayDate > $1.displayDate }
        case .oldest: items.sort { $0.displayDate < $1.displayDate }
        case .kind: items.sort { ($0.kind.rawValue, $1.displayDate) < ($1.kind.rawValue, $0.displayDate) }
        case .place: items.sort { ($0.placeName ?? "~", $1.displayDate) < ($1.placeName ?? "~", $0.displayDate) }
        }
        return items
    }

    private var grid: some View {
        ScrollView {
            let items = filtered
            if items.isEmpty {
                ContentUnavailableView.search(text: searchText).padding(.top, 80)
            } else {
                summaryBar(items)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { artwork in
                        NavigationLink(value: artwork.id) {
                            StickerCard(artwork: artwork)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let a = artworks.first(where: { $0.id == id }) { ArtworkDetailView(artwork: a) }
        }
    }

    private func summaryBar(_ items: [Artwork]) -> some View {
        let places = Set(items.compactMap(\.localityName)).count
        let seriesCount = Set(items.compactMap { $0.series?.id }).count
        return HStack(spacing: 14) {
            stat("\(items.count)", "pieces")
            if places > 0 { stat("\(places)", "cities") }
            if seriesCount > 0 { stat("\(seriesCount)", "series") }
            Spacer()
            if let kindFilter {
                Button { self.kindFilter = nil } label: { HStack(spacing: 4) { KindChip(kind: kindFilter); Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary) } }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func stat(_ value: String, _ label: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.display(18)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }
}
