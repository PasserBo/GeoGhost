import MapKit
import SwiftData
import SwiftUI

/// Publishing preview (spec: publishing): everything other people will see, what stays private,
/// and how many posts are left. Publishing itself happens only on the button.
struct PublishSheet: View {
    @Bindable var artwork: Artwork
    let state: OnlineState

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var quota: PublishQuota?
    @State private var loadError: String?
    @State private var publishError: String?
    @State private var isPublishing = false
    @State private var showProfileSetup = false
    @State private var result: PublishState?

    private var blurred: CLLocationCoordinate2D? { artwork.coordinate.map(LocationBlur.snap) }
    private var quotaUsedUp: Bool { quota.map { $0.monthRemaining == 0 || $0.dayRemaining == 0 } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let result { resultCard(result) } else { preview }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PaperBackground())
            .navigationTitle(result == nil ? "Publish to the world map" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result != nil { Button("Done") { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if result == nil {
                    Button { start() } label: {
                        HStack { if isPublishing { ProgressView().tint(.white) }; Text("Publish") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isPublishing || quotaUsedUp || artwork.coordinate == nil)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .task { await load() }
            .sheet(isPresented: $showProfileSetup) {
                ProfileSetupSheet(state: state) { Task { await publish() } }
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 16) {
            ArtworkImageView(artwork: artwork, variant: .cutout)
                .padding(20)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)) }

            card {
                Text("What others will see").font(.headline)
                row("Area", areaText)
                row("Found on", artwork.displayDate.formatted(date: .long, time: .omitted))
                row("Kind", String(localized: artwork.kind.title))
                row("By", state.profile?.nickname ?? String(localized: "Your nickname"))
                if let blurred {
                    Map(initialPosition: .region(MKCoordinateRegion(center: blurred, latitudinalMeters: 700, longitudinalMeters: 700)),
                        interactionModes: []) {
                        MapCircle(center: blurred, radius: 80).foregroundStyle(Theme.accent.opacity(0.25)).stroke(Theme.accent, lineWidth: 2)
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("The location is shown only to within about 100 m.").font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }

            card {
                Label("Stays on this phone", systemImage: "lock.fill").font(.headline)
                Text("The original photo, the exact location, the time of day, your device, notes and tags are never published.")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }

            card {
                if let quota {
                    if quota.monthRemaining == 0 {
                        Text("You've used this month's \(quota.monthLimit) posts. You can publish again on \(quota.resetsAt.formatted(date: .abbreviated, time: .omitted)).")
                            .foregroundStyle(.red)
                    } else if quota.dayRemaining == 0 {
                        Text("You've reached today's limit. You can publish again tomorrow.").foregroundStyle(.red)
                    } else {
                        Text("You can publish \(quota.monthRemaining) more this month.")
                    }
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
                Text("New publishers' first posts are checked before others can see them. Retracting a post doesn't give the post back.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                Link("Community rules", destination: OnlineState.rulesURL).font(.caption)
            }

            if let publishError {
                Text(publishError).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var areaText: String {
        let country = artwork.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        let parts = [artwork.localityName, country].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Unknown area") : parts.joined(separator: ", ")
    }

    private func resultCard(_ state: PublishState) -> some View {
        VStack(spacing: 14) {
            Image(systemName: state == .published ? "globe.asia.australia.fill" : "hourglass")
                .font(.system(size: 48)).foregroundStyle(Theme.accent)
            Text(state == .published ? "Published" : "Sent for review").font(.display(24))
            Text(state == .published
                 ? "Everyone can now see this piece on the world map."
                 : "Others will see this piece once it has been checked, usually within a day. Until then only you can see it.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 60)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    // MARK: Actions

    private func load() async {
        do {
            try await state.loadProfile()
            quota = try await state.services.publishing.quota()
        } catch {
            if let shown = state.handle(error) { loadError = OnlineMessage.text(for: shown) } else { dismiss() }
        }
    }

    private func start() {
        if state.needsProfileSetup { showProfileSetup = true } else { Task { await publish() } }
    }

    private func publish() async {
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }
        do {
            result = try await ArtworkPublisher(backend: state.services.publishing, context: context).publish(artwork)
        } catch {
            guard let shown = state.handle(error) else { dismiss(); return }
            if case OnlineError.refused(.profileRequired) = shown { showProfileSetup = true; return }
            if case OnlineError.refused(.termsRequired) = shown { showProfileSetup = true; return }
            publishError = OnlineMessage.text(for: shown)
            quota = try? await state.services.publishing.quota()
        }
    }
}
