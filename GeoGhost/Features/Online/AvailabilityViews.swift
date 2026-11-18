import SwiftUI

/// Where the update buttons go (spec: online-availability).
enum AppStoreLink {
    /// App Store Connect › App Information › Apple ID.
    static let appID = "0000000000"
    static let url = URL(string: "https://apps.apple.com/app/id\(appID)")!
}

/// Shown instead of an online feature when this version is below the operator's minimum.
/// Local collecting keeps working, so this never blocks the rest of the app.
struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.app").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text("Update GeoGhost to use online features").font(.headline).multilineTextAlignment(.center)
            Text("This version can no longer use the world map, publishing, reporting or blocking. Your collection and your own map keep working.")
                .font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            Button("Update in the App Store") { openURL(AppStoreLink.url) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}

/// The operator's notice, in the app's language (else English).
struct OnlineNoticeView: View {
    let text: String

    var body: some View {
        Label { Text(text).font(.footnote) } icon: { Image(systemName: "megaphone.fill").foregroundStyle(Theme.accent) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
