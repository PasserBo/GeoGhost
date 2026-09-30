import CoreLocation
import SwiftData
import SwiftUI

/// Final confirmation before an artwork enters the collection.
struct SaveArtworkSheet: View {
    @Bindable var model: CaptureFlowModel
    let cutout: CGImage
    /// `keepEditing` = the user wants to pick another piece from the same photo.
    let onSaved: (_ keepEditing: Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ArtworkKind = .sticker
    @State private var kindWasSetByUser = false
    @State private var note = ""
    @State private var tagText = ""
    @State private var place: PlaceInfo?
    @State private var isLookingUpPlace = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(decorative: cutout, scale: 1)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 260)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)) }
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                    kindPicker

                    VStack(spacing: 0) {
                        row(icon: "mappin.and.ellipse", tint: .red) {
                            if let place { Text(place.placeName) }
                            else if model.metadata.coordinate == nil { Text("No location").foregroundStyle(Theme.inkSecondary) }
                            else if isLookingUpPlace { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Looking up place…") }.foregroundStyle(Theme.inkSecondary) }
                            else if let c = model.metadata.coordinate { Text(String(format: "%.5f, %.5f", c.latitude, c.longitude)).monospacedDigit() }
                        }
                        Divider().padding(.leading, 44)
                        row(icon: "clock", tint: .blue) {
                            HStack {
                                Text((model.metadata.capturedAt ?? Date()).shortDisplay)
                                if model.metadata.capturedAtIsEstimated { Text("(import time)").foregroundStyle(Theme.inkSecondary) }
                            }
                        }
                        if let device = model.metadata.deviceModel {
                            Divider().padding(.leading, 44)
                            row(icon: "camera", tint: .gray) { Text(device).foregroundStyle(Theme.inkSecondary) }
                        }
                    }
                    .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                    VStack(spacing: 0) {
                        TextField("Add a note", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(14)
                        Divider().padding(.leading, 14)
                        TextField("Tags, separated by spaces", text: $tagText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                    }
                    .background(Theme.paperElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PaperBackground())
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        Task { await save(keepEditing: false) }
                    } label: {
                        HStack { if isSaving { ProgressView().tint(.white) }; Text("Save") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
                    Button {
                        Task { await save(keepEditing: true) }
                    } label: {
                        Label("Save and pick another from this photo", systemImage: "plus.square.on.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(isSaving)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.paper)
            }
            .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .task { await lookupPlace() }
        .task { await suggestKind() }
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ArtworkKind.allCases) { k in
                    Button {
                        kind = k; kindWasSetByUser = true
                    } label: {
                        Label(k.title, systemImage: k.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(kind == k ? k.tint : Theme.paperElevated, in: Capsule())
                            .foregroundStyle(kind == k ? .white : Theme.ink)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func row<Content: View>(icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 20)
            content()
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func lookupPlace() async {
        guard let c = model.metadata.coordinate else { return }
        isLookingUpPlace = true
        place = await ReverseGeocoder.shared.lookup(c)
        isLookingUpPlace = false
    }

    private func suggestKind() async {
        let covers = model.coversMostOfFrame
        let suggestion = await Task.detached(priority: .utility) { try? KindClassifier.suggest(for: cutout, coversMostOfFrame: covers) }.value
        if let suggestion, !kindWasSetByUser { kind = suggestion.kind }
    }

    private func save(keepEditing: Bool) async {
        isSaving = true
        defer { isSaving = false }
        guard let originalData = model.originalData else { return }
        let input = ArtworkSaver.Input(
            originalData: originalData, originalExtension: model.originalExtension, cutout: cutout,
            cutoutRect: model.cutoutRect, segmentationMode: model.segmentationMode, metadata: model.metadata,
            kind: kind, kindIsUserSet: kindWasSetByUser, note: note,
            tags: tagText.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init), place: place)
        do {
            try await ArtworkSaver.save(input, in: context)
            onSaved(keepEditing)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
