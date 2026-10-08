import SwiftUI

/// Explains GeoGhost Pro. Only lists what ships today; the founder note promises future perks without specifics.
struct PaywallView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pro = services.pro
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "seal.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
                        Text("GeoGhost Pro").font(.display(30))
                        Text("Collecting is free and unlimited, always. Pro makes what you collect look its best.")
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("rectangle.portrait.on.rectangle.portrait.angled.fill", "Every share card style", "Polaroid, Poster and Minimal, on top of the free Field note.")
                        benefit("seal", "Cards without the credit", "Turn off the small GeoGhost mark on your cards.")
                        benefit("photo.badge.checkmark", "Full-resolution stickers", "Export transparent PNGs at the size they were cut out, instead of 1600 px.")
                        benefit("star.circle.fill", "Founding supporter", "GeoGhost will go online — sharing stickers and a world map of finds. Early supporters will get a thank-you when it does.")
                    }
                    .padding(18)
                    .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                    if pro.isPro {
                        Label { Text("GeoGhost Pro is active").fontWeight(.semibold) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            Button { Task { await pro.purchase() } } label: {
                                if pro.isLoading { ProgressView().tint(.white) } else {
                                    Text(pro.product.map { String(localized: "Unlock for \($0.displayPrice)") } ?? String(localized: "Unlock Pro"))
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(pro.isLoading)
                            Text("One-time purchase. No subscription.").font(.caption).foregroundStyle(Theme.inkSecondary)
                            Button("Restore purchase") { Task { await pro.restore() } }.font(.subheadline)
                            if let e = pro.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(PaperBackground())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { if pro.product == nil { await pro.load() } }
            .onChange(of: pro.isPro) { _, isPro in if isPro { dismiss() } }
        }
    }

    private func benefit(_ symbol: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
