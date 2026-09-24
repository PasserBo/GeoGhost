import MapKit
import SwiftData
import SwiftUI

/// One design, every place it has been seen: a route on the map plus a timeline.
struct SeriesDetailView: View {
    @Bindable var series: ArtSeries
    @Environment(\.modelContext) private var context
    @State private var isRenaming = false
    @State private var draftTitle = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if series.coordinates.count >= 1 { routeMap }
                stats
                timeline
            }
            .padding(16).padding(.bottom, 40)
        }
        .background(PaperBackground())
        .navigationTitle(series.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draftTitle = series.title; isRenaming = true } label: { Image(systemName: "pencil") }
            }
        }
        .alert("Name this series", isPresented: $isRenaming) {
            TextField("e.g. Pink cat sticker", text: $draftTitle)
            Button("Save") { series.title = draftTitle.trimmingCharacters(in: .whitespaces); try? context.save() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var routeMap: some View {
        let coords = series.coordinates
        return Map(initialPosition: .region(region(for: coords)), interactionModes: [.pan, .zoom]) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
            }
            ForEach(series.members.filter { $0.coordinate != nil }) { a in
                Annotation("", coordinate: a.coordinate!) { ArtworkPin(artwork: a, size: 40) }
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statBox("\(series.encounterCount)", "encounters")
            statBox("\(series.distinctLocalities.count)", "places")
            statBox(spanText, "span")
        }
    }

    private var spanText: String {
        guard let f = series.firstSeen, let l = series.lastSeen else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: f, to: l).day ?? 0
        return days == 0 ? String(localized: "1 day") : String(localized: "\(days + 1) days")
    }

    private func statBox(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.display(22))
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(series.members.enumerated()), id: \.element.id) { i, a in
                NavigationLink { ArtworkDetailView(artwork: a) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle().fill(Theme.accent).frame(width: 10, height: 10).padding(.top, 22)
                            if i < series.encounterCount - 1 { Rectangle().fill(Theme.rule).frame(width: 2).frame(maxHeight: .infinity) }
                        }
                        .frame(width: 10)
                        ArtworkImageView(artwork: a, variant: .thumbnail).frame(width: 56, height: 56).padding(.vertical, 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.placeName ?? String(localized: "Unknown place")).font(.headline).foregroundStyle(Theme.ink)
                            Text(a.displayDate.shortDisplay).font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.vertical, 10)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.inkSecondary).padding(.top, 20)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coords.first else { return MKCoordinateRegion(.world) }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coords { minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude); minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude) }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.6), longitudeDelta: max(0.005, (maxLon - minLon) * 1.6))
        return MKCoordinateRegion(center: center, span: span)
    }
}
