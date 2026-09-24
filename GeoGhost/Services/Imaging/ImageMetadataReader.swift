import Foundation
import ImageIO

/// Reads EXIF / TIFF / GPS metadata out of raw image bytes.
enum ImageMetadataReader {
    static func read(_ data: Data) -> CaptureMetadata {
        var meta = CaptureMetadata()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return meta }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        // Pixel size, respecting orientation.
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        if orientation >= 5 { meta.pixelWidth = h; meta.pixelHeight = w } else { meta.pixelWidth = w; meta.pixelHeight = h }

        // Timestamp.
        if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String {
            let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            meta.capturedAt = parseExifDate(dateString, offset: offset)
        }

        meta.deviceModel = tiff[kCGImagePropertyTIFFModel] as? String
        meta.lensModel = exif[kCGImagePropertyExifLensModel] as? String

        // GPS.
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            meta.latitude = latRef.uppercased() == "S" ? -abs(lat) : abs(lat)
            meta.longitude = lonRef.uppercased() == "W" ? -abs(lon) : abs(lon)
            meta.locationSource = .exif
            if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
                let ref = gps[kCGImagePropertyGPSAltitudeRef] as? Int ?? 0
                meta.altitude = ref == 1 ? -alt : alt
            }
            if let hpos = gps[kCGImagePropertyGPSHPositioningError] as? Double { meta.horizontalAccuracy = hpos }
            if let dir = gps[kCGImagePropertyGPSImgDirection] as? Double { meta.heading = dir }
        }
        return meta
    }

    /// EXIF dates look like "2026:09:24 14:32:07", optionally with a "+09:00" offset in a sibling field.
    static func parseExifDate(_ string: String, offset: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset, let tz = timeZone(fromOffset: offset) {
            f.timeZone = tz
        } else {
            f.timeZone = .current
        }
        return f.date(from: string)
    }

    static func timeZone(fromOffset offset: String) -> TimeZone? {
        // "+09:00" / "-05:30" / "Z"
        if offset == "Z" { return TimeZone(secondsFromGMT: 0) }
        let sign: Int = offset.hasPrefix("-") ? -1 : 1
        let parts = offset.dropFirst().split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }

    /// Build a GPS dictionary suitable for `AVCapturePhotoSettings.metadata`.
    static func gpsDictionary(latitude: Double, longitude: Double, altitude: Double?, accuracy: Double?, heading: Double?, date: Date) -> [String: Any] {
        var d: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(latitude),
            kCGImagePropertyGPSLatitudeRef as String: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(longitude),
            kCGImagePropertyGPSLongitudeRef as String: longitude >= 0 ? "E" : "W",
        ]
        if let altitude {
            d[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            d[kCGImagePropertyGPSAltitudeRef as String] = altitude < 0 ? 1 : 0
        }
        if let accuracy { d[kCGImagePropertyGPSHPositioningError as String] = accuracy }
        if let heading, heading >= 0 {
            d[kCGImagePropertyGPSImgDirection as String] = heading
            d[kCGImagePropertyGPSImgDirectionRef as String] = "T"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy:MM:dd"
        d[kCGImagePropertyGPSDateStamp as String] = df.string(from: date)
        df.dateFormat = "HH:mm:ss"
        d[kCGImagePropertyGPSTimeStamp as String] = df.string(from: date)
        return d
    }
}
