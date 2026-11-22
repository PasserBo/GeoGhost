import SwiftUI
import UIKit

/// One card the user can pick in a share sheet.
///
/// The deck that previews and exports cards only knows this type, and a card only knows its own
/// content, so a new kind of card is a new view plus one more option — nothing else changes.
struct ShareCardOption: Identifiable {
    /// Stable name of the card, also used in the exported file's name.
    let id: String
    let title: LocalizedStringResource
    /// Shown in the deck, but sharing it asks the sheet to unlock it first.
    var isLocked = false
    /// Draws the card at `ShareCardLayout.size`. Called for the preview and again for the export.
    let card: @MainActor () -> AnyView

    init(id: String, title: LocalizedStringResource, isLocked: Bool = false,
         @ViewBuilder card: @escaping @MainActor () -> some View) {
        self.id = id
        self.title = title
        self.isLocked = isLocked
        self.card = { AnyView(card()) }
    }
}

/// Every share card is 4:5, laid out in points at 360×450 and exported at 1080×1350.
enum ShareCardLayout {
    static let size = CGSize(width: 360, height: 450)
    static let exportScale: CGFloat = 3
}

/// Fixed light palette so cards look the same whatever the device appearance.
enum ShareCardPalette {
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.905)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let inkSecondary = Color(red: 0.42, green: 0.40, blue: 0.37)
}

/// The small GeoGhost mark that signs a card.
struct ShareCardCredit: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "seal.fill").font(.system(size: 9))
            Text(verbatim: "GeoGhost").font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .opacity(0.7)
    }
}

enum ShareCardRenderer {
    /// Renders a card to a 1080×1350 PNG in the temporary directory.
    @MainActor static func renderPNG(_ option: ShareCardOption) -> URL? {
        let card = option.card()
            .frame(width: ShareCardLayout.size.width, height: ShareCardLayout.size.height)
            .clipped()
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardLayout.exportScale
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "GeoGhost-card-\(option.id).png")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
