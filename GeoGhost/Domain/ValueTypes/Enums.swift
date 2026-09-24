import SwiftUI

/// What kind of street piece an artwork is.
enum ArtworkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sticker, graffiti, mural, poster, tag, other

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .sticker: "Sticker"
        case .graffiti: "Graffiti"
        case .mural: "Mural"
        case .poster: "Poster"
        case .tag: "Tag"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .sticker: "seal.fill"
        case .graffiti: "paintbrush.pointed.fill"
        case .mural: "photo.artframe"
        case .poster: "doc.richtext.fill"
        case .tag: "scribble.variable"
        case .other: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .sticker: Color(red: 1.00, green: 0.42, blue: 0.17)
        case .graffiti: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .mural: Color(red: 0.13, green: 0.62, blue: 0.55)
        case .poster: Color(red: 0.94, green: 0.72, blue: 0.14)
        case .tag: Color(red: 0.20, green: 0.55, blue: 0.95)
        case .other: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}

/// Where the coordinates attached to an artwork came from.
enum LocationSource: String, Codable, Sendable {
    case device, exif, manual, none
}

/// How the cutout was produced.
enum SegmentationMode: String, Codable, Sendable {
    /// Vision picked the subject, user accepted the default.
    case auto
    /// Vision segmented, user changed the selected instances.
    case autoAdjusted
    /// User drew a rectangle; cutout is opaque.
    case manualCrop

    var isTransparent: Bool { self != .manualCrop }
}

enum Visibility: String, Codable, Sendable {
    case privateOnly, publicShared
}
