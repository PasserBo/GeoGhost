import SwiftData
import SwiftUI

/// Settings → Online (specs: online-identity, publishing): nickname, retract everything, delete
/// the online data. Local pieces are never touched except becoming private.
struct OnlineSettingsSection: View {
    let state: OnlineState

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Artwork> { $0.publishStateRaw != "unpublished" }) private var shared: [Artwork]
    @State private var showNickname = false
    @State private var confirmRetractAll = false
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        Section {
            Button { showNickname = true } label: {
                LabeledContent("Nickname", value: state.profile?.nickname ?? String(localized: "Not set"))
            }
            .foregroundStyle(Theme.ink)
            LabeledContent("Published pieces", value: "\(shared.count)")
            NavigationLink("Blocked users") { BlockedUsersView(state: state) }
            Button("Retract all published pieces", role: .destructive) { confirmRetractAll = true }
                .disabled(shared.isEmpty || isWorking)
            Button("Delete my online data", role: .destructive) { confirmDelete = true }
                .disabled(isWorking)
            Link("Community rules", destination: OnlineState.rulesURL)
            if isWorking { ProgressView() }
            if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Online")
        } footer: {
            Text("You take part as a guest, without an account. Your guest identity stays on this phone, even if you reinstall GeoGhost.")
        }
        .task { try? await loadIfSignedIn() }
        .sheet(isPresented: $showNickname) { ProfileSetupSheet(state: state, purpose: .changeNickname) }
        .confirmationDialog("Retract all published pieces?", isPresented: $confirmRetractAll, titleVisibility: .visible) {
            Button("Retract all", role: .destructive) {
                run { try await ArtworkPublisher(backend: state.services.publishing, context: context).retractAll(shared) }
            }
        } message: { Text("They disappear from the world map for everyone and become private again on this phone.") }
        .confirmationDialog("Delete your online data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete online data", role: .destructive) { run { try await state.deleteOnlineData(context: context) } }
        } message: {
            Text("Your published pieces, likes, saved pieces, blocked users and nickname are deleted from the server. The pieces in your collection stay on this phone and become private. This cannot be undone.")
        }
    }

    /// Reading the profile must not create a guest just because Settings was opened.
    private func loadIfSignedIn() async throws {
        guard await state.hasIdentity else { return }
        try await state.loadProfile()
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

/// App-wide alert for a lost guest identity (spec: online-identity › 线上身份失效时告知用户).
struct IdentityExpiredAlert: ViewModifier {
    let state: OnlineState?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.alert("Your online identity is no longer valid", isPresented: Binding(
            get: { state?.identityExpired ?? false }, set: { if !$0 { state?.identityExpired = false } })) {
            Button("Start as a new guest") {
                guard let state else { return }
                Task { await state.acceptExpiredIdentity(context: context) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Pieces you published before can no longer be managed from this phone. They become private here; to have them taken down from the world map, contact support.")
        }
    }
}
