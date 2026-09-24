import SwiftUI

/// Shows the segmented photo; tap to pick / add subjects.
struct SegmentationEditorView: View {
    @Bindable var model: CaptureFlowModel
    @State private var isFinishing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ZStack {
                    if let preview = model.previewImage {
                        let fitted = fittedRect(imageSize: CGSize(width: preview.width, height: preview.height), in: geo.size)
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                            .onTapGesture { location in
                                let p = CGPoint(x: (location.x - fitted.minX) / fitted.width, y: (location.y - fitted.minY) / fitted.height)
                                guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
                                model.toggleInstance(atNormalized: p)
                            }
                            .animation(.easeInOut(duration: 0.15), value: model.previewImage.map { ObjectIdentifier($0) })
                    } else if let full = model.fullImage {
                        Image(decorative: full, scale: 1).resizable().scaledToFit()
                    }
                    if model.isRenderingPreview && model.previewImage == nil { ProgressView().tint(.white) }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            footer
        }
        .background(Color.black)
    }

    private var header: some View {
        HStack {
            Button { model.reset() } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Retake")
            Spacer()
            VStack(spacing: 2) {
                Text("Tap to choose the piece").font(.subheadline.weight(.semibold))
                if model.instanceCount > 1 {
                    Text("\(model.instanceCount) subjects found · tap more to add").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Menu {
                Button { model.selectAll() } label: { Label("Select all subjects", systemImage: "square.stack.3d.up") }
                Button { model.switchToManualCrop() } label: { Label("Crop by hand", systemImage: "crop") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if model.selectedArea > 0 && model.selectedArea < 0.005 {
                Label("Quite small — get closer for a sharper cutout", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.yellow)
            }
            HStack(spacing: 12) {
                Button { model.switchToManualCrop() } label: {
                    Label("Crop by hand", systemImage: "crop")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    isFinishing = true
                    Task { await model.finishAutomatic(); isFinishing = false }
                } label: {
                    HStack {
                        if isFinishing { ProgressView().tint(.white) } else { Image(systemName: "checkmark") }
                        Text("Use this cutout")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isFinishing || model.selection.isEmpty)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }
}
