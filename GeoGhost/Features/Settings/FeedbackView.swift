import PhotosUI
import SwiftUI

/// Settings → Send feedback: a message, an optional screenshot and an optional email for a reply.
/// Sent as a report (ReportQueue); if offline it waits on the device and goes out later.
struct FeedbackView: View {
    private enum Outcome { case sent, queued }

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var email = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var isSending = false
    @State private var outcome: Outcome?
    @FocusState private var messageFocused: Bool

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .focused($messageFocused)
                } header: {
                    Text("Ideas, problems, anything")
                } footer: {
                    Text("GeoGhost is made by one person, and every message is read.")
                }
                Section {
                    let hasScreenshot = screenshot != nil // the label closure is @Sendable
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(hasScreenshot ? "Choose a different screenshot" : "Attach a screenshot", systemImage: "photo")
                    }
                    if let screenshot {
                        Image(uiImage: screenshot).resizable().scaledToFit().frame(maxHeight: 220)
                        Button("Remove screenshot", role: .destructive) { self.screenshot = nil; photoItem = nil }
                    }
                } footer: {
                    Text("Optional.")
                }
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Optional — only if you'd like a reply.")
                }
                Section {
                    LabeledContent("Sent with", value: "GeoGhost \(Bundle.main.versionString) · \(Report.deviceModel) · \(Report.osVersion)")
                } footer: {
                    Text("Your photos, locations and notes are not included unless you attach a screenshot of them.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() } else {
                        Button("Send") { Task { await send() } }.disabled(trimmedMessage.isEmpty)
                    }
                }
            }
            .task(id: photoItem) {
                guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                screenshot = UIImage(data: data)
            }
            .task {
                // Focusing while the sheet is still animating in is ignored.
                try? await Task.sleep(for: .milliseconds(500))
                messageFocused = true
            }
            .alert(outcome == .sent ? "Thank you!" : "Saved", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { dismiss() } })) {
                Button("OK") { dismiss() }
            } message: {
                outcome == .sent
                    ? Text("Your feedback was sent.")
                    : Text("You seem to be offline. Your feedback is saved and will be sent automatically.")
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        var payload: [String: Any] = ["message": trimmedMessage]
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { payload["email"] = trimmedEmail }
        let jpeg = await Task.detached(priority: .userInitiated) { [screenshot] in screenshot.flatMap(Self.jpeg) }.value
        guard let report = Report.make(.feedback, payload: payload, screenshot: jpeg) else { return }
        await ReportQueue.shared.enqueue(report)
        await ReportQueue.shared.flush()
        outcome = await ReportQueue.shared.isQueued(id: report.id) ? .queued : .sent
    }

    /// Small enough for the endpoint's 2 MB limit after base64.
    private nonisolated static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 1600 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = scaled.jpegData(compressionQuality: 0.7) else { return nil }
        return data.count > 1_200_000 ? scaled.jpegData(compressionQuality: 0.45) : data
    }
}
