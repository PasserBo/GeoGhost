import MapKit
import SwiftUI
import UIKit

/// An image from the online backend (public post images are HEIC, which iOS decodes natively).
/// Kept in a small memory cache so panning back and forth doesn't download again.
struct RemoteImageView: View {
    let url: URL?

    nonisolated(unsafe) private static let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 300
        return c
    }()

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Theme.inkSecondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if let hit = Self.cache.object(forKey: url as NSURL) { image = hit; return }
        failed = false
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = await Task.detached(operation: { UIImage(data: data)?.preparingForDisplay() }).value else {
                failed = true
                return
            }
            Self.cache.setObject(decoded, forKey: url as NSURL)
            image = decoded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// A public post on the world map: the sticker in a paper frame, like the pins of one's own pieces.
struct ExplorePostPin: View {
    let post: ExplorePost
    let config: OnlineConfig
    var size: CGFloat = 44

    var body: some View {
        RemoteImageView(url: post.thumbKey.map(config.imageURL))
            .padding(4)
            .frame(width: size, height: size)
            .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(post.artworkKind.tint, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

/// Several public posts in one grid cell: a representative sticker and how many there are.
struct ExploreClusterPin: View {
    let post: ExplorePost
    let config: OnlineConfig

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ExplorePostPin(post: post, config: config, size: 48)
            Text("\(post.cellCount)")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .offset(x: 8, y: -8)
        }
    }
}

/// Someone's public post (spec: explore-map › 他人贴纸的详情): only what was published.
struct RemotePostSheet: View {
    let post: ExplorePost
    let config: OnlineConfig
    /// Reporting and blocking (spec: content-safety); nil hides them.
    var state: OnlineState?

    @Environment(\.dismiss) private var dismiss
    /// Someone else's post: known once the identity was checked, so one's own post never offers these.
    @State private var isOthers = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var reported = false
    @State private var isBlocking = false
    @State private var blockError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteImageView(url: (post.imageKey ?? post.thumbKey).map(config.imageURL))
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 260)
                        .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)) }
                    KindChip(kind: post.artworkKind)
                    Text(area).font(.display(24))
                    VStack(alignment: .leading, spacing: 6) {
                        if let day = foundOn { row("Found on", day) }
                        row("By", post.authorNickname ?? String(localized: "Unknown"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    Text("The location is shown only to within about 100 m.").font(.caption).foregroundStyle(Theme.inkSecondary)
                    if let blockError { Text(blockError).font(.footnote).foregroundStyle(.red) }
                }
                .padding(16)
            }
            .background(PaperBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if state != nil, isOthers {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isBlocking { ProgressView() } else {
                            Menu {
                                Button("Report this piece", systemImage: "flag") { showReport = true }
                                Button("Block \(authorName)", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .task {
                guard let state else { return }
                isOthers = await state.services.identity.userID != post.authorId
            }
            .sheet(isPresented: $showReport, onDismiss: {
                // Reported: the post leaves this user's map and the detail closes
                // (spec: content-safety › 举报后自己不再看到).
                guard reported else { return }
                NotificationCenter.default.post(name: .onlinePostReported, object: post.id)
                dismiss()
            }) {
                if let state { ReportSheet(post: post, state: state) { reported = true } }
            }
            .confirmationDialog("Block \(authorName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) { block() }
            } message: {
                Text("You won't see their pieces on the world map anymore. They won't be told. You can unblock them in Settings.")
            }
        }
    }

    private var authorName: String { post.authorNickname ?? String(localized: "Unknown user") }

    private func block() {
        guard let state else { return }
        isBlocking = true
        blockError = nil
        Task {
            defer { isBlocking = false }
            do {
                try await state.services.safety.block(userID: post.authorId)
                // The world map drops the author's posts (spec: content-safety › 屏蔽发布者).
                NotificationCenter.default.post(name: .onlineBlocksChanged, object: post.authorId)
                dismiss()
            } catch {
                if let shown = state.handle(error) { blockError = OnlineMessage.text(for: shown) }
            }
        }
    }

    private var area: String {
        let country = post.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        let parts = [post.locality, country].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Unknown area") : parts.joined(separator: ", ")
    }

    /// The server's calendar day, shown as that same day whatever the phone's time zone.
    private var foundOn: String? {
        guard let s = post.capturedOn else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return s }
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}
