import SwiftUI

/// Report someone's public post (spec: content-safety › 举报贴纸). Stays open with the choice and
/// note kept when submitting fails; after it was sent, says the user won't see the piece again.
struct ReportSheet: View {
    let post: ExplorePost
    let state: OnlineState
    /// Called after the server accepted the report; the sheet then shows the confirmation.
    var onReported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ReportDraft()
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            if sent { confirmation } else { form }
        }
        .interactiveDismissDisabled(isSending)
    }

    private var confirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.accent)
            Text("Thanks for reporting").font(.title2.weight(.semibold))
            Text("You won't see this piece again. We review every report within 24 hours.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.inkSecondary)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground())
    }

    private var form: some View {
        Form {
            Section {
                Picker("Reason", selection: $draft.reason) {
                    ForEach(ReportReason.allCases) { reason in
                        Text(reason.title).tag(Optional(reason))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Why are you reporting this piece?")
            }
            Section {
                TextField("Add details (optional)", text: $draft.note, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Details")
            } footer: {
                if (draft.trimmedNote?.count ?? 0) > ReportDraft.noteLimit {
                    Text("Use at most 500 characters.").foregroundStyle(.red)
                } else if draft.reason?.requiresNote == true, draft.trimmedNote == nil {
                    Text("Tell us what's wrong with this piece.")
                } else {
                    Text("Reports are anonymous. We review every report within 24 hours.")
                }
            }
            if let errorText {
                Section { Text(errorText).font(.footnote).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if isSending { ProgressView() } else {
                    Button("Send") { send() }.disabled(!draft.canSubmit)
                }
            }
        }
    }

    private func send() {
        guard let reason = draft.reason, draft.canSubmit else { return }
        isSending = true
        errorText = nil
        Task {
            defer { isSending = false }
            do {
                try await state.services.safety.report(postID: post.id, reason: reason, note: draft.trimmedNote)
                onReported()
                sent = true
            } catch {
                if let shown = state.handle(error) { errorText = OnlineMessage.text(for: shown) } else { dismiss() }
            }
        }
    }
}

/// Settings → Online → Blocked users (spec: content-safety › 查看和解除屏蔽).
struct BlockedUsersView: View {
    let state: OnlineState

    @State private var users: [BlockedUser] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var working: Set<UUID> = []

    var body: some View {
        List {
            if let actionError {
                Text(actionError).font(.footnote).foregroundStyle(.red)
            }
            ForEach(users) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.nickname ?? String(localized: "Unknown user"))
                        Text(user.blockedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    if working.contains(user.id) {
                        ProgressView()
                    } else {
                        Button("Unblock") { unblock(user) }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .overlay {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load blocked users", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if loaded, users.isEmpty {
                ContentUnavailableView("No blocked users", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("To block someone, open one of their pieces on the world map."))
            } else if !loaded {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Blocked users")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loadError = nil
        do {
            users = try await state.services.safety.blockedUsers()
            loaded = true
        } catch {
            if let shown = state.handle(error) { loadError = OnlineMessage.text(for: shown) } else { users = []; loaded = true }
        }
    }

    private func unblock(_ user: BlockedUser) {
        working.insert(user.id)
        actionError = nil
        Task {
            defer { working.remove(user.id) }
            do {
                try await state.services.safety.unblock(userID: user.id)
                users.removeAll { $0.id == user.id }
                NotificationCenter.default.post(name: .onlineBlocksChanged, object: nil)
            } catch {
                if let shown = state.handle(error) { actionError = OnlineMessage.text(for: shown) }
            }
        }
    }
}
