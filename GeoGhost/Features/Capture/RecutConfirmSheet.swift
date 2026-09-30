import SwiftData
import SwiftUI

/// Confirms replacing an existing artwork's cutout with a fresh selection from the same photo.
struct RecutConfirmSheet: View {
    @Bindable var model: CaptureFlowModel
    let cutout: CGImage
    let artwork: Artwork
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    column("Before") { ArtworkImageView(artwork: artwork, variant: .cutout) }
                    Image(systemName: "arrow.right").font(.title2).foregroundStyle(Theme.inkSecondary)
                    column("After") { Image(decorative: cutout, scale: 1).resizable().scaledToFit() }
                }
                .frame(height: 220)
                Text("Notes, tags, place and series stay as they are. Only the cutout changes.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(16)
            .background(PaperBackground())
            .navigationTitle("Edit piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await replace() } } label: {
                    HStack { if isSaving { ProgressView().tint(.white) }; Text("Replace") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.paper)
            }
            .alert("Could not replace", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func column<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func replace() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await ArtworkSaver.replaceCutout(of: artwork, with: cutout, rect: model.cutoutRect, mode: model.segmentationMode, in: context)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
