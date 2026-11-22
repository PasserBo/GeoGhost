import CoreGraphics
import Foundation

/// The outline of a country, as rings of (longitude, latitude) points.
struct CountryOutline: Sendable, Equatable {
    let rings: [[CGPoint]]

    /// The box around every ring, in degrees.
    var bounds: CGRect {
        var box = CGRect.null
        for ring in rings {
            for point in ring { box = box.union(CGRect(origin: point, size: .zero)) }
        }
        return box
    }
}

/// Country outlines bundled with the app (`CountryOutlines.json`: ISO code → rings of [lon, lat]).
/// Used for the small locator on share cards, so it only needs to be recognisable at thumbnail size:
/// each country is its main landmass and the sizeable parts near it, simplified to about 10 km.
/// Made from Natural Earth (public domain) by scripts/build-country-outlines.py.
final class CountryOutlines: Sendable {
    static let shared = CountryOutlines(bundle: .main)

    private let table: [String: [[[Double]]]]

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "CountryOutlines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) else {
            table = [:]
            return
        }
        self.table = table
    }

    func outline(for countryCode: String?) -> CountryOutline? {
        guard let countryCode, let rings = table[countryCode.uppercased()], !rings.isEmpty else { return nil }
        return CountryOutline(rings: rings.map { ring in ring.filter { $0.count == 2 }.map { CGPoint(x: $0[0], y: $0[1]) } })
    }
}
