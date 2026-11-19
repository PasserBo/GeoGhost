import SwiftUI

/// Shown instead of the save sheet after cutting out a practice photo: nothing is saved; next, the user's own photo.
struct PracticeDoneSheet: View {
    let cutout: CGImage
    let hasNextSample: Bool
    let onTakePhoto: () -> Void
    let onNextSample: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(decorative: cutout, scale: 1)
                .resizable().scaledToFit()
                .frame(maxHeight: 220)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background { CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)) }
            Text("Nice cut!").font(.title2.bold())
            Text("Practice pieces aren't added to your collection. Now try one you find on the street.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onTakePhoto) {
                Label("Take a photo", systemImage: "camera.fill").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
            HStack {
                if hasNextSample { Button("Try another sample", action: onNextSample) }
                Spacer()
                Button("Done", action: onDone)
            }
            .tint(Theme.accent)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }
}
