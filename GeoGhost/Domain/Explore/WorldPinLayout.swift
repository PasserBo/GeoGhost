import CoreGraphics
import Foundation
import MapKit

/// Decides what the world map draws for the pieces in view: which get a thumbnail, which stand
/// behind another piece's thumbnail as a count, and which are left as small dots.
///
/// A phone screen holds only so many thumbnails before they cover each other and the map, so the
/// newest pieces get them and nothing is ever drawn as a bare number.
enum WorldPinLayout {
    struct Group: Identifiable, Equatable {
        enum Style: Equatable { case thumbnail, dot }

        /// The piece that stands for the group; keeps its identity while zooming regroups the rest.
        let representative: ExplorePost
        /// The pieces known to be here, newest first. A server cell knows only its newest.
        var members: [ExplorePost]
        /// How many pieces the group stands for (more than `members` for a server cell).
        var count: Int
        var style: Style

        var id: UUID { representative.id }
        var coordinate: CLLocationCoordinate2D { representative.coordinate }
        /// Everything it stands for is in `members`.
        var isFullyKnown: Bool { members.count == count }
    }

    static let maxThumbnails = 20
    /// Thumbnails closer than this (in points) would overlap, so the later one joins the earlier.
    static let spacing: CGFloat = 58

    /// `posts` newest first; `project` gives each piece's place in a view of `size` (nil: not on
    /// the map). Pieces outside the view are left out.
    static func arrange(_ posts: [ExplorePost], size: CGSize, maxThumbnails: Int = maxThumbnails, spacing: CGFloat = spacing,
                        project: (CLLocationCoordinate2D) -> CGPoint?) -> [Group] {
        guard size.width > 0, size.height > 0 else { return [] }
        var groups: [Group] = []
        var points: [CGPoint] = []
        for post in posts {
            guard let point = project(post.coordinate) else { continue }
            // A margin, so a piece just off the edge doesn't pop in and out while panning.
            guard point.x > -spacing, point.x < size.width + spacing, point.y > -spacing, point.y < size.height + spacing else { continue }
            if let index = points.firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < spacing }) {
                groups[index].members.append(post)
                groups[index].count += max(1, post.cellCount)
            } else {
                groups.append(Group(representative: post, members: [post], count: max(1, post.cellCount), style: .thumbnail))
                points.append(point)
            }
        }
        for index in groups.indices where index >= maxThumbnails { groups[index].style = .dot }
        return groups
    }

    /// The same, placing pieces by their position in a north-up map that shows `region`.
    static func arrange(_ posts: [ExplorePost], region: MKCoordinateRegion, size: CGSize,
                        maxThumbnails: Int = maxThumbnails, spacing: CGFloat = spacing) -> [Group] {
        guard let projection = Projection(region: region, size: size) else { return [] }
        return arrange(posts, size: size, maxThumbnails: maxThumbnails, spacing: spacing) { projection.point(for: $0) }
    }

    /// Where a coordinate falls in a north-up map showing `region` in a view of `size`.
    struct Projection {
        private let center: MKMapPoint
        private let size: CGSize
        private let scale: Double

        init?(region: MKCoordinateRegion, size: CGSize) {
            let north = min(85, region.center.latitude + region.span.latitudeDelta / 2)
            let south = max(-85, region.center.latitude - region.span.latitudeDelta / 2)
            let top = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: region.center.longitude))
            let bottom = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: region.center.longitude))
            guard bottom.y > top.y else { return nil }
            // The map fits the region's height; the width follows from the view's shape.
            scale = Double(size.height) / (bottom.y - top.y)
            center = MKMapPoint(x: MKMapPoint(region.center).x, y: (top.y + bottom.y) / 2)
            self.size = size
        }

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            let p = MKMapPoint(coordinate)
            // The shorter way round the globe, so pieces across the 180° line land on the right side.
            var dx = p.x - center.x
            let world = MKMapSize.world.width
            if dx > world / 2 { dx -= world } else if dx < -world / 2 { dx += world }
            return CGPoint(x: Double(size.width) / 2 + dx * scale, y: Double(size.height) / 2 + (p.y - center.y) * scale)
        }
    }
}
