import SwiftUI
import UIKit

/// GeoGhost visual language: a paper field guide with bold marker-orange accents.
enum Theme {
    static let paper = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1) : UIColor(red: 0.965, green: 0.945, blue: 0.905, alpha: 1)
    })
    static let paperElevated = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1) : UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1) : UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
    })
    static let inkSecondary = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.65, alpha: 1) : UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1)
    })
    static let rule = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 0.10)
    })
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.17)

    static let cornerRadius: CGFloat = 18
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Subtle checkerboard used behind transparent cutouts.
struct CheckerboardBackground: View {
    var cell: CGFloat = 12
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)), with: .color(.primary.opacity(0.06)))
                }
            }
        }
        .background(Theme.paperElevated)
    }
}

struct PaperBackground: View {
    var body: some View {
        Theme.paper.ignoresSafeArea()
    }
}

struct KindChip: View {
    let kind: ArtworkKind
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName)
            if !compact { Text(kind.title) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, 5)
        .background(kind.tint.opacity(0.16), in: Capsule())
        .foregroundStyle(kind.tint)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var action: (label: LocalizedStringResource, run: () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkSecondary)
            Text(title).font(.display(22))
            Text(message).font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            if let action {
                Button(action: action.run) { Text(action.label).fontWeight(.semibold) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension Date {
    var shortDisplay: String { formatted(date: .abbreviated, time: .shortened) }
}
