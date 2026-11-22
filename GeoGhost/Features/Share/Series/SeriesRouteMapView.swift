import SwiftUI

/// The still map of a series with its route drawn on top: every stop, a dashed line through them
/// in the order they happened, the names of the two farthest apart and, for a local map, a small
/// outline of the country showing where this is.
struct SeriesRouteMapView: View {
    let map: RouteMapImage
    let stats: SeriesStats
    let locator: CountryOutline?

    var body: some View {
        GeometryReader { geo in
            let points = map.points.map { CGPoint(x: $0.x * geo.size.width, y: $0.y * geo.size.height) }
            ZStack(alignment: .topLeading) {
                Image(uiImage: map.image).resizable().frame(width: geo.size.width, height: geo.size.height)
                if points.count > 1 {
                    Path { path in path.addLines(points) }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                }
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle().fill(Theme.accent)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .position(point)
                }
                ForEach(labels(points: points, in: geo.size)) { label in
                    Text(label.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShareCardPalette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(ShareCardPalette.paper.opacity(0.9), in: Capsule())
                        .frame(maxWidth: Label.maxWidth)
                        .position(label.center)
                }
                // The snapshot carries Apple's own Maps mark in its bottom-left corner. It is the map's
                // credit, so nothing of ours goes over it: the locator sits at the top.
                // Only when the stops are on the outline: far-off territories aren't in the data.
                if let locator, let focus = focus, locator.bounds.insetBy(dx: -0.5, dy: -0.5).contains(focus) {
                    CountryLocatorView(outline: locator, focus: focus).padding(6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The middle of the stops, as (longitude, latitude).
    private var focus: CGPoint? {
        guard !stats.stops.isEmpty else { return nil }
        let count = Double(stats.stops.count)
        return CGPoint(x: stats.stops.map(\.longitude).reduce(0, +) / count, y: stats.stops.map(\.latitude).reduce(0, +) / count)
    }

    private struct Label: Identifiable {
        static let maxWidth: CGFloat = 110
        let id: Int
        let text: String
        let center: CGPoint
    }

    /// Names for the two farthest stops (or the only one), kept inside the map and off each other.
    private func labels(points: [CGPoint], in size: CGSize) -> [Label] {
        let indices: [Int]
        if let farthest = stats.farthest { indices = [farthest.first, farthest.second] }
        else if stats.stops.count == 1 { indices = [0] }
        else { indices = [] }

        var result: [Label] = []
        for index in indices where index < points.count {
            guard let name = stats.stops[index].placeName?.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { continue }
            let point = points[index]
            // Names go on the outer sides of the pair, so they don't sit on the route between them.
            let partner = indices.first { $0 != index && $0 < points.count }.map { points[$0] }
            var below = partner.map { point.y > $0.y } ?? (point.y < size.height * 0.6)
            if point.y - 15 < 10 { below = true }
            if point.y + 15 > size.height - 10 { below = false }
            // A name below a stop near the bottom-left corner would sit on the map's own Maps mark.
            if point.x < size.width * 0.4, point.y + 15 > size.height * 0.6 { below = false }
            let y = min(size.height - 10, max(22, point.y + (below ? 15 : -15)))
            let x = min(size.width - Label.maxWidth / 2 + 20, max(Label.maxWidth / 2 - 20, point.x))
            result.append(Label(id: index, text: name, center: CGPoint(x: x, y: y)))
        }
        return result
    }
}

/// A thumbnail of a country with a dot on the place in question.
struct CountryLocatorView: View {
    let outline: CountryOutline
    /// (longitude, latitude).
    let focus: CGPoint

    var body: some View {
        Canvas { context, size in
            let bounds = outline.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            // Degrees of longitude shrink away from the equator; without this a country looks stretched.
            let squeeze = max(0.2, cos(bounds.midY * .pi / 180))
            let inset: CGFloat = 5
            let scale = min((size.width - inset * 2) / (bounds.width * squeeze), (size.height - inset * 2) / bounds.height)
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(x: size.width / 2 + (point.x - bounds.midX) * squeeze * scale,
                        y: size.height / 2 - (point.y - bounds.midY) * scale)
            }
            var land = Path()
            for ring in outline.rings where ring.count > 2 {
                land.addLines(ring.map(place))
                land.closeSubpath()
            }
            context.fill(land, with: .color(ShareCardPalette.inkSecondary.opacity(0.55)))
            let dot = place(focus)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)), with: .color(Theme.accent))
        }
        .frame(width: 46, height: 40)
        .background(ShareCardPalette.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(ShareCardPalette.ink.opacity(0.12), lineWidth: 0.5))
    }
}
