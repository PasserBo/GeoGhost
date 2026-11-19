import SwiftUI

/// Nickname and community rules (spec: online-identity). Shown before the first post, again when
/// the rules change, and from Settings to change the nickname.
struct ProfileSetupSheet: View {
    enum Purpose { case beforePublishing, changeNickname }

    let state: OnlineState
    var purpose: Purpose = .beforePublishing
    /// Called after the profile was saved.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var agreed = false
    @State private var isSaving = false
    @State private var errorText: String?
    @FocusState private var nicknameFocused: Bool

    static let maxNicknameLength = 24

    private var trimmed: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nicknameValid: Bool { !trimmed.isEmpty && trimmed.count <= Self.maxNicknameLength }
    /// Agreement is asked for whenever the user has not agreed to the current rules.
    private var asksForRules: Bool { state.needsProfileSetup }
    private var lockedUntil: Date? { purpose == .changeNickname ? state.nicknameChangeAvailableAt : nil }
    /// New members are paused: only a first nickname is affected (spec: online-availability).
    private var joinPaused: Bool { state.appConfig.signupsPaused && state.profile == nil }
    private var canSave: Bool { nicknameValid && (!asksForRules || agreed) && lockedUntil == nil && !joinPaused && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $nickname)
                        .focused($nicknameFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(lockedUntil != nil)
                } header: {
                    Text("Nickname")
                } footer: {
                    if let lockedUntil {
                        Text("You can change your nickname again on \(lockedUntil.formatted(date: .abbreviated, time: .omitted)).")
                    } else if !trimmed.isEmpty, trimmed.count > Self.maxNicknameLength {
                        Text("Use at most 24 characters.").foregroundStyle(.red)
                    } else if !nickname.isEmpty, trimmed.isEmpty {
                        Text("A nickname can't be only spaces.").foregroundStyle(.red)
                    } else {
                        Text("Shown next to the pieces you publish. You don't need an account.")
                    }
                }

                if asksForRules {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            rule("Only publish what you found in public space.")
                            rule("No sexual, violent or hateful content, and nothing that harasses anyone.")
                            rule("No faces, licence plates, addresses or other personal information.")
                            rule("No ads or spam.")
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                        Link("Read the full community rules", destination: OnlineState.rulesURL)
                        Toggle("I agree to the community rules", isOn: $agreed)
                    } header: {
                        Text("Community rules")
                    } footer: {
                        Text("There is zero tolerance for objectionable content. Posts that break the rules are removed, and their authors can be blocked from publishing.")
                    }
                }

                if joinPaused {
                    Section { Text("New members can't join right now. Please try again later.").foregroundStyle(.red) }
                } else if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(purpose == .changeNickname ? "Change nickname" : "Before you publish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button(purpose == .changeNickname ? "Save" : "Continue") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
            .onAppear {
                if nickname.isEmpty { nickname = state.profile?.nickname ?? "" }
                if lockedUntil == nil { nicknameFocused = true }
            }
        }
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "checkmark.circle").foregroundStyle(Theme.accent) }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await state.saveProfile(nickname: trimmed)
            onSaved()
            dismiss()
        } catch {
            guard let shown = state.handle(error) else { dismiss(); return }
            errorText = OnlineMessage.text(for: shown)
        }
    }
}
