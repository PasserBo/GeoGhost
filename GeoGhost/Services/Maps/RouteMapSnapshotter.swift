import MapKit
import UIKit

/// A still map, and where each requested coordinate falls on it (0…1 across and down), so a route
/// can be drawn over it without asking MapKit again.
struct RouteMapImage: @unchecked Sendable {
    let image: UIImage
    /// The size in points the map was made for, and must be shown at for the points to line up.
    let size: CGSize
    let points: [CGPoint]
}

enum RouteMapSnapshotter {
    /// Never show less than about 1.6 km: closer than that a map can single out a building.
    static let minimumLatitudeSpan = 0.015

    /// The region that holds every coordinate with room around them. The margin is wide enough to
    /// keep the outermost stops clear of the Maps mark the snapshot carries in its bottom-left corner.
    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else { return MKCoordinateRegion(.world) }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(minimumLatitudeSpan, (maxLat - minLat) * 2.0)),
                                    longitudeDelta: min(350, max(minimumLatitudeSpan, (maxLon - minLon) * 1.9)))
        return MKCoordinateRegion(center: center, span: span)
    }

    /// A light, muted map without points of interest. Returns nil when there is nothing to show,
    /// the map can't be loaded (no network), or it takes longer than `timeout`.
    @MainActor
    static func snapshot(coordinates: [CLLocationCoordinate2D], size: CGSize, scale: CGFloat = ShareCardLayout.exportScale,
                         timeout: Duration = .seconds(8)) async -> RouteMapImage? {
        guard !coordinates.isEmpty else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = region(for: coordinates)
        options.size = size
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = .light
            traits.displayScale = scale
        }
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        let snapshotter = MKMapSnapshotter(options: options)
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<RouteMapImage?, Never>) in
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.run {
                    snapshotter.cancel()
                    continuation.resume(returning: nil)
                }
            }
            snapshotter.start(with: .main) { snapshot, _ in
                once.run {
                    guard let snapshot else { continuation.resume(returning: nil); return }
                    let points = coordinates.map { coordinate in
                        let point = snapshot.point(for: coordinate)
                        return CGPoint(x: point.x / size.width, y: point.y / size.height)
                    }
                    continuation.resume(returning: RouteMapImage(image: snapshot.image, size: size, points: points))
                }
            }
        }
    }

    /// Lets whichever of the map and the timeout comes first answer, and the other do nothing.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { body() }
        }
    }
}
