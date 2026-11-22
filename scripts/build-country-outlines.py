"""Reduce Natural Earth's 50m countries to thumbnail outlines: ISO code -> rings of [lon, lat].

Keeps a country's main landmass and the sizeable parts near it, simplified to about 10 km, which is
plenty for a 46x40 pt locator. The result is committed as GeoGhost/Resources/CountryOutlines.json.

Source (public domain): ne_50m_admin_0_countries.geojson from
https://github.com/nvkelso/natural-earth-vector/tree/master/geojson
Usage: python3 scripts/build-country-outlines.py <countries.geojson> GeoGhost/Resources/CountryOutlines.json
"""
import json, math, sys

TOLERANCE = 0.1       # degrees
MIN_SHARE = 0.03      # of the largest part's area
MAX_AWAY = 25.0       # degrees from the largest part's centre

def area(ring):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:] + ring[:1]))) / 2

def centre(ring):
    return (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))

def simplify(points, tolerance):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (x1, y1), (x2, y2) = points[first], points[last]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        worst, index = 0.0, None
        for i in range(first + 1, last):
            x, y = points[i]
            d = abs(dy * (x - x1) - dx * (y - y1)) / length if length else math.hypot(x - x1, y - y1)
            if d > worst:
                worst, index = d, i
        if index is not None and worst > tolerance:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]

source, target = sys.argv[1], sys.argv[2]
table = {}
for feature in json.load(open(source))["features"]:
    props = feature["properties"]
    code = props.get("ISO_A2_EH") or props.get("ISO_A2")
    if not code or code == "-99" or len(code) != 2:
        continue
    geometry = feature["geometry"]
    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    outers = [[[float(x), float(y)] for x, y in polygon[0]] for polygon in polygons if polygon]
    if not outers:
        continue
    outers.sort(key=area, reverse=True)
    main, cx_cy = area(outers[0]), centre(outers[0])
    rings = []
    for ring in outers:
        c = centre(ring)
        if area(ring) < main * MIN_SHARE or math.hypot(c[0] - cx_cy[0], c[1] - cx_cy[1]) > MAX_AWAY:
            continue
        reduced = simplify(ring, TOLERANCE)
        # A country smaller than the tolerance would vanish; keep its outline as it is.
        if len(reduced) < 4:
            reduced = ring
        if len(reduced) >= 4:
            rings.append([[round(x, 2), round(y, 2)] for x, y in reduced])
    if rings and code not in table:
        table[code] = rings
json.dump(dict(sorted(table.items())), open(target, "w"), separators=(",", ":"))
print(len(table), "countries;", sum(len(r) for rings in table.values() for r in rings), "points")
for code in ("JP", "US", "FR", "CN", "SG", "GB", "TW", "KR"):
    print(code, [len(r) for r in table.get(code, [])])
