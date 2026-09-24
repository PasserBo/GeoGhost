import SwiftUI
import UIKit

/// Shows the photo; tap or long-press a piece to lift it. Works with or without Vision instances.
struct SegmentationEditorView: View {
    @Bindable var model: CaptureFlowModel
    @State private var isFinishing = false
    @State private var showHint = true

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ZStack {
                    if let preview = model.previewImage ?? model.fullImage {
                        let fitted = fittedRect(imageSize: CGSize(width: preview.width, height: preview.height), in: geo.size)
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                            .overlay { PickGestureView { pt in handlePick(pt, in: fitted, container: geo.size) } }
                    }
                    if model.isPicking {
                        ProgressView().tint(.white).controlSize(.large)
                            .padding(18).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if showHint && !model.hasSelection && !model.isPicking {
                        hintBubble
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            footer
        }
        .background(Color.black)
        .sensoryFeedback(.selection, trigger: model.selectedArea)
        .sensoryFeedback(.error, trigger: model.lastPickFailed) { _, new in new }
    }

    private func handlePick(_ location: CGPoint, in fitted: CGRect, container: CGSize) {
        let p = CGPoint(x: (location.x - fitted.minX) / fitted.width, y: (location.y - fitted.minY) / fitted.height)
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        showHint = false
        model.pick(atNormalized: p)
    }

    private var hintBubble: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap.fill").font(.title2)
            Text("Long-press the piece to lift it").font(.subheadline.weight(.semibold))
            Text("Press again to add more").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var header: some View {
        HStack {
            Button { model.reset() } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Retake")
            Spacer()
            VStack(spacing: 2) {
                Text(model.hasSelection ? "Press to add · press a selection to remove" : "Press the piece you want").font(.subheadline.weight(.semibold))
                if model.lastPickFailed {
                    Text("Couldn't isolate that spot — try its edge or crop by hand").font(.caption).foregroundStyle(.yellow)
                } else if model.instanceCount > 1 {
                    Text("\(model.instanceCount) subjects found").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            .multilineTextAlignment(.center)
            Spacer()
            Menu {
                if model.instanceCount > 0 {
                    Button { model.selectAll() } label: { Label("Select all subjects", systemImage: "square.stack.3d.up") }
                }
                Button { model.clearSelection() } label: { Label("Clear selection", systemImage: "xmark.circle") }
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
                Button { model.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo")
                Button { model.switchToManualCrop() } label: {
                    Image(systemName: "crop")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Crop by hand")
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
                .disabled(isFinishing || !model.hasSelection || model.isRenderingPreview)
                .opacity(model.hasSelection ? 1 : 0.5)
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

/// Tap *or* long-press, both reporting the touch location. UIKit recognizers give us the point reliably.
private struct PickGestureView: UIViewRepresentable {
    let onPick: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        long.minimumPressDuration = 0.3
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(long)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.onPick = onPick }
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject {
        var onPick: (CGPoint) -> Void
        init(onPick: @escaping (CGPoint) -> Void) { self.onPick = onPick }
        @objc func tapped(_ g: UITapGestureRecognizer) { onPick(g.location(in: g.view?.superview)) }
        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPick(g.location(in: g.view?.superview))
        }
    }
}
