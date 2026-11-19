import SwiftData
import SwiftUI

/// The piece's place on the world map, on its detail page (spec: publishing).
struct PublishStatusCard: View {
    @Bindable var artwork: Artwork
    let state: OnlineState

    @Environment(\.modelContext) private var context
    @State private var showPublish = false
    @State private var confirmRetract = false
    @State private var isWorking = false
    @State private var errorText: String?

    private var publisher: ArtworkPublisher { ArtworkPublisher(backend: state.services.publishing, context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if isWorking { ProgressView() }
            }
            actions
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .sheet(isPresented: $showPublish) { PublishSheet(artwork: artwork, state: state) }
        .confirmationDialog("Retract this piece?", isPresented: $confirmRetract, titleVisibility: .visible) {
            Button("Retract", role: .destructive) { run { try await publisher.retract(artwork) } }
        } message: {
            Text("It disappears from the world map for everyone and becomes private again. The post used this month is not given back.")
        }
        .task(id: artwork.remotePostID) {
            // Pick up review results and hidden posts whenever the page opens.
            guard artwork.publishState.hasRemoteCopy else { return }
            try? await publisher.refreshStates([artwork])
        }
    }

    @ViewBuilder private var actions: some View {
        switch artwork.publishState {
        case .unpublished:
            Button { showPublish = true } label: { Label("Publish to the world map", systemImage: "globe.asia.australia") }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(artwork.coordinate == nil || isWorking)
        case .uploading:
            HStack {
                Button { run { try await publisher.publish(artwork) } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                retractButton
            }
            .disabled(isWorking)
        case .pending, .reReview, .published, .rejected:
            retractButton.disabled(isWorking)
        }
    }

    private var retractButton: some View {
        Button(role: .destructive) { confirmRetract = true } label: { Label("Retract", systemImage: "arrow.uturn.backward") }
            .buttonStyle(.bordered)
    }

    private var icon: String {
        switch artwork.publishState {
        case .unpublished: "lock.fill"
        case .uploading: "exclamationmark.arrow.triangle.2.circlepath"
        case .pending: "hourglass"
        case .reReview: "exclamationmark.shield.fill"
        case .published: "globe.asia.australia.fill"
        case .rejected: "eye.slash.fill"
        }
    }

    private var tint: Color {
        switch artwork.publishState {
        case .published: Theme.accent
        case .uploading, .rejected: .red
        case .reReview: .orange
        default: Theme.inkSecondary
        }
    }

    private var title: LocalizedStringKey {
        switch artwork.publishState {
        case .unpublished: "Private"
        case .uploading: "Not finished"
        case .pending: "In review"
        case .reReview: "Being checked again"
        case .published: "On the world map"
        case .rejected: "Not approved"
        }
    }

    private var detail: String {
        switch artwork.publishState {
        case .unpublished:
            artwork.coordinate == nil
                ? String(localized: "Pieces need a location to appear on the world map.")
                : String(localized: "Only you can see this piece.")
        case .uploading:
            String(localized: "Publishing was interrupted. Trying again won't use another post.")
        case .pending:
            String(localized: "Only you can see it until it has been checked.")
        case .reReview:
            String(localized: "Several people reported it, so it's hidden from others until it has been checked again.")
        case .published:
            artwork.publishedAt.map { String(localized: "Public since \($0.formatted(date: .abbreviated, time: .omitted))") }
                ?? String(localized: "Everyone can see this piece.")
        case .rejected:
            String(localized: "It didn't pass review or was hidden after reports. Others can't see it.")
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false }
            do { try await action() } catch {
                if let shown = state.handle(error) { errorText = OnlineMessage.text(for: shown) }
            }
        }
    }
}
