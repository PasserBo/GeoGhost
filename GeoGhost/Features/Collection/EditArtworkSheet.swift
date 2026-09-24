import SwiftData
import SwiftUI

struct EditArtworkSheet: View {
    @Bindable var artwork: Artwork
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tagText = ""
    @State private var kind: ArtworkKind = .sticker
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(ArtworkKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(2...6)
                }
                Section("Tags") {
                    TextField("Tags, separated by spaces", text: $tagText).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let series = artwork.series {
                    Section("Series") {
                        LabeledContent("Belongs to", value: series.displayTitle)
                        Button("Remove from series", role: .destructive) {
                            artwork.series = nil
                            artwork.isSeriesManuallyAssigned = true
                            if series.encounterCount <= 1 { context.delete(series) }
                        }
                    }
                }
            }
            .navigationTitle("Edit piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
            .onAppear {
                kind = artwork.kind
                note = artwork.note
                tagText = artwork.tagList.map(\.name).joined(separator: " ")
            }
        }
    }

    private func save() {
        if kind != artwork.kind { artwork.kind = kind; artwork.kindIsUserSet = true; artwork.kindIsAutoDetected = false }
        artwork.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = tagText.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        artwork.tags = try? ArtworkSaver.tags(named: names, in: context)
        try? context.save()
        dismiss()
    }
}
