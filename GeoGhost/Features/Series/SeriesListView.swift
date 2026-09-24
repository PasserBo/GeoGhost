import SwiftData
import SwiftUI

/// Designs seen more than once, plus the ability to build series by hand.
struct SeriesListView: View {
    @Query(sort: \ArtSeries.createdAt, order: .reverse) private var series: [ArtSeries]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if series.isEmpty {
                    EmptyStateView(systemImage: "rectangle.stack", title: "No series yet",
                                   message: "When you collect the same sticker in two places, GeoGhost links them here automatically.")
                } else {
                    List {
                        ForEach(series.sorted { $0.encounterCount > $1.encounterCount }) { s in
                            NavigationLink { SeriesDetailView(series: s) } label: { SeriesRow(series: s) }
                                .listRowBackground(Theme.paperElevated)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    
                }
            }
            .background(PaperBackground())
            .navigationTitle("Series")
        }
    }

    private func delete(_ offsets: IndexSet) {
        let sorted = series.sorted { $0.encounterCount > $1.encounterCount }
        for i in offsets {
            let s = sorted[i]
            for a in s.members { a.series = nil; a.isSeriesManuallyAssigned = true }
            context.delete(s)
        }
        try? context.save()
    }
}

struct SeriesRow: View {
    let series: ArtSeries
    var body: some View {
        HStack(spacing: 12) {
            if let cover = series.cover {
                ArtworkImageView(artwork: cover, variant: .thumbnail).frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayTitle).font(.headline)
                Text("\(series.encounterCount) encounters · \(series.distinctLocalities.count) places").font(.caption).foregroundStyle(Theme.inkSecondary)
                if let first = series.firstSeen, let last = series.lastSeen, first != last {
                    Text("\(first.formatted(date: .abbreviated, time: .omitted)) → \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            HStack(spacing: -12) {
                ForEach(series.members.dropFirst().prefix(3)) { a in
                    ArtworkImageView(artwork: a, variant: .thumbnail).frame(width: 34, height: 34)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
