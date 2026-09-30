import SwiftUI
import UIKit

/// The subject picker.
///
/// Gestures — press is *try*, release is *commit*, swipe down is *throw away*:
/// - hold: tentative selection appears (Vision instance or grown region); release to add
/// - hold on a selected piece: tentative drill-down into the smaller piece under the finger; release to replace
/// - hold + drag left/right: tighten / loosen the region tolerance live
/// - hold + swipe down: discard (or delete the piece under the finger)
/// - hold + swipe up: absorb enclosing shapes (sticker border around its artwork)
/// - tap a selected piece: remove it
/// - pinch / drag: zoom & pan; double-tap: zoom in at point or reset
/// - two-finger tap: undo
///
/// Zooming also scopes detection: Vision re-runs on the visible crop and region growth can't leave it.
struct SegmentationEditorView: View {
    @Bindable var model: CaptureFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var isFinishing = false
    @State private var showHint = true

    // Viewport transform (about the container centre).
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gestureStartZoom: CGFloat = 1
    @State private var gestureStartPan: CGSize = .zero
    @State private var viewportSettleTask: Task<Void, Never>?
    /// Lasso being drawn, in container points (for the overlay only; the model gets normalized points).
    @State private var lassoTrail: [CGPoint] = []

    private let maxZoom: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let container = geo.size
                let imageSize = model.fullImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
                let fitted = fittedRect(imageSize: imageSize, in: container)
                ZStack {
                    Color.black
                    Group {
                        if let preview = model.previewImage ?? model.fullImage {
                            Image(decorative: preview, scale: 1)
                                .resizable()
                                .frame(width: fitted.width, height: fitted.height)
                                .position(x: fitted.midX, y: fitted.midY)
                        }
                        if let tv = model.tentativeVisual, model.hold != nil {
                            LiftedPieceView(visual: tv, fitted: fitted).allowsHitTesting(false)
                        }
                        if let hl = model.lastPickHighlight {
                            PickPopView(highlight: hl, fitted: fitted).allowsHitTesting(false)
                        }
                    }
                    .scaleEffect(zoom)
                    .offset(pan)
                    .animation(.easeOut(duration: 0.18), value: zoom)

                    EditorGestureView(
                        onHoldBegan: { pt in beginHold(pt, fitted: fitted, container: container) },
                        onHoldChanged: { t in model.updateHold(translation: t) },
                        onHoldEnded: { model.endHold() },
                        onHoldCancelled: { model.cancelHold() },
                        onTap: { pt in if let n = normalized(pt, fitted: fitted, container: container) { model.tap(at: n) } },
                        onDoubleTap: { pt in toggleZoom(at: pt, fitted: fitted, container: container) },
                        onPinch: { scale, state in pinch(scale, state: state, fitted: fitted, container: container) },
                        onPan: { t, state in drag(t, state: state, fitted: fitted, container: container) },
                        onTwoFingerTap: { model.undo() },
                        onLasso: { pts, state in lasso(pts, state: state, fitted: fitted, container: container) }
                    )

                    if lassoTrail.count > 1 {
                        Path { p in p.addLines(lassoTrail) }
                            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .allowsHitTesting(false)
                    }

                    if model.isPicking || model.isAnalyzingViewport {
                        ProgressView().tint(.white).controlSize(.regular)
                            .padding(12).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                    if showHint && !model.hasSelection && model.hold == nil && !model.isPicking {
                        hintBubble.allowsHitTesting(false)
                    }
                    if let hold = model.hold {
                        holdStatus(hold).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14).allowsHitTesting(false)
                    }
                }
                .frame(width: container.width, height: container.height)
                .clipped()
                .onChange(of: zoom) { _, _ in scheduleViewportUpdate(fitted: fitted, container: container) }
                .onChange(of: pan) { _, _ in scheduleViewportUpdate(fitted: fitted, container: container) }
            }
            footer
        }
        .background(Color.black)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.pieces.count)
        .sensoryFeedback(.error, trigger: model.lastPickFailed) { _, new in new }
        .sensoryFeedback(.selection, trigger: model.hold?.intent)
    }

    // MARK: Coordinate mapping

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Container point → unzoomed layout point.
    private func unzoomed(_ c: CGPoint, container: CGSize) -> CGPoint {
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        return CGPoint(x: center.x + (c.x - pan.width - center.x) / zoom, y: center.y + (c.y - pan.height - center.y) / zoom)
    }

    private func normalized(_ c: CGPoint, fitted: CGRect, container: CGSize) -> CGPoint? {
        guard fitted.width > 0 else { return nil }
        let u = unzoomed(c, container: container)
        let n = CGPoint(x: (u.x - fitted.minX) / fitted.width, y: (u.y - fitted.minY) / fitted.height)
        guard (0...1).contains(n.x), (0...1).contains(n.y) else { return nil }
        return n
    }

    private func visibleRect(fitted: CGRect, container: CGSize) -> CGRect {
        let a = unzoomed(.zero, container: container)
        let b = unzoomed(CGPoint(x: container.width, y: container.height), container: container)
        let r = CGRect(x: (a.x - fitted.minX) / fitted.width, y: (a.y - fitted.minY) / fitted.height,
                       width: (b.x - a.x) / fitted.width, height: (b.y - a.y) / fitted.height)
        return r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func clampPan(_ p: CGSize, fitted: CGRect, container: CGSize) -> CGSize {
        let maxX = max(0, (fitted.width * zoom - container.width) / 2 + fitted.minX * zoom)
        let maxY = max(0, (fitted.height * zoom - container.height) / 2 + fitted.minY * zoom)
        return CGSize(width: min(max(p.width, -maxX), maxX), height: min(max(p.height, -maxY), maxY))
    }

    private func scheduleViewportUpdate(fitted: CGRect, container: CGSize) {
        viewportSettleTask?.cancel()
        viewportSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.setViewport(visibleRect(fitted: fitted, container: container))
        }
    }

    // MARK: Gesture handlers

    private func beginHold(_ pt: CGPoint, fitted: CGRect, container: CGSize) {
        guard let n = normalized(pt, fitted: fitted, container: container) else { return }
        showHint = false
        model.beginHold(at: n)
    }

    private func toggleZoom(at pt: CGPoint, fitted: CGRect, container: CGSize) {
        if zoom > 1.01 {
            zoom = 1; pan = .zero
        } else {
            let target: CGFloat = 2.5
            let center = CGPoint(x: container.width / 2, y: container.height / 2)
            // Keep the tapped point under the finger.
            zoom = target
            pan = clampPan(CGSize(width: (center.x - pt.x) * (target - 1), height: (center.y - pt.y) * (target - 1)), fitted: fitted, container: container)
        }
    }

    private func pinch(_ scale: CGFloat, state: UIGestureRecognizer.State, fitted: CGRect, container: CGSize) {
        switch state {
        case .began:
            gestureStartZoom = zoom; gestureStartPan = pan
        case .changed:
            let z = min(max(gestureStartZoom * scale, 1), maxZoom)
            zoom = z
            pan = clampPan(CGSize(width: gestureStartPan.width * z / gestureStartZoom, height: gestureStartPan.height * z / gestureStartZoom), fitted: fitted, container: container)
        default:
            if zoom < 1.05 { zoom = 1; pan = .zero }
        }
    }

    private func drag(_ t: CGSize, state: UIGestureRecognizer.State, fitted: CGRect, container: CGSize) {
        guard zoom > 1.01 else { return }
        switch state {
        case .began: gestureStartPan = pan
        case .changed: pan = clampPan(CGSize(width: gestureStartPan.width + t.width, height: gestureStartPan.height + t.height), fitted: fitted, container: container)
        default: break
        }
    }

    private func lasso(_ pts: [CGPoint], state: UIGestureRecognizer.State, fitted: CGRect, container: CGSize) {
        switch state {
        case .began, .changed:
            lassoTrail = pts
            showHint = false
        case .ended:
            let normalized = pts.compactMap { normalizedUnclamped($0, fitted: fitted, container: container) }
            lassoTrail = []
            model.lassoEnded(normalized)
        default:
            lassoTrail = []
        }
    }

    /// Like `normalized` but clamps instead of rejecting points slightly outside the photo.
    private func normalizedUnclamped(_ c: CGPoint, fitted: CGRect, container: CGSize) -> CGPoint? {
        guard fitted.width > 0 else { return nil }
        let u = unzoomed(c, container: container)
        return CGPoint(x: min(1, max(0, (u.x - fitted.minX) / fitted.width)), y: min(1, max(0, (u.y - fitted.minY) / fitted.height)))
    }

    // MARK: Chrome

    private var hintBubble: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap.fill").font(.title2)
            Text("Hold on the piece, or draw a loop around it").font(.subheadline.weight(.semibold))
            Text("Pinch to zoom · two fingers to move").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.opacity)
    }

    @ViewBuilder private func holdStatus(_ hold: CaptureFlowModel.Hold) -> some View {
        let text: LocalizedStringResource = switch hold.intent {
        case .add: hold.tentative == nil ? "Looking…" : "Release to add · swipe down to cancel"
        case .replace: hold.tentative == nil ? "Looking for something smaller…" : "Release to replace with this"
        case .discard: "Release to cancel"
        case .delete: "Release to remove this piece"
        case .expand: "Expanding ×\(hold.layers)"
        }
        VStack(spacing: 8) {
            if hold.axis == .horizontal {
                ToleranceBar(value: hold.tolerance)
            }
            Text(text)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.6), in: Capsule())
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: hold.intent)
    }

    private var header: some View {
        HStack {
            Button { model.reset() } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Retake")
            Spacer()
            VStack(spacing: 2) {
                Text(model.isEditingExisting ? "Hold or loop to re-select this piece" : model.hasSelection ? "Hold or loop to add · tap a piece to remove" : "Hold on the piece, or loop around it").font(.subheadline.weight(.semibold))
                if model.lastPickFailed {
                    Text("Couldn't isolate that — try drawing a loop around it").font(.caption).foregroundStyle(.yellow)
                } else if model.isEditingExisting && model.pieces.first?.isStored == true {
                    Text("Showing the current cutout · a new selection replaces it").font(.caption).foregroundStyle(.white.opacity(0.7))
                } else if model.pieces.count > 1 {
                    Text("\(model.pieces.count) pieces selected").font(.caption).foregroundStyle(.white.opacity(0.7))
                } else if model.savedCount > 0 {
                    Text("\(model.savedCount) saved from this photo").font(.caption).foregroundStyle(.white.opacity(0.7))
                } else if zoom > 1.01 {
                    Text("Detecting within view · \(model.instanceCount) subjects").font(.caption).foregroundStyle(.white.opacity(0.7))
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
                Button { zoom = 1; pan = .zero } label: { Label("Reset zoom", systemImage: "arrow.down.right.and.arrow.up.left") }
                Button { model.switchToManualCrop() } label: { Label("Crop by hand", systemImage: "crop") }
                Divider()
                NavigationLink { GestureHelpView() } label: { Label("Gesture guide", systemImage: "questionmark.circle") }
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
                Label("Quite small — zoom in for a sharper cutout", systemImage: "plus.magnifyingglass")
                    .font(.caption).foregroundStyle(.yellow)
            }
            HStack(spacing: 12) {
                Button { model.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.headline).frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo")
                Button { model.switchToManualCrop() } label: {
                    Image(systemName: "crop").font(.headline).frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Crop by hand")
                if !model.hasSelection && model.savedCount > 0 {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
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
                    .disabled(isFinishing || !model.hasSelection || model.isRenderingPreview || model.hold != nil)
                    .opacity(model.hasSelection ? 1 : 0.5)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

/// Live tolerance readout while dragging horizontally during a hold.
private struct ToleranceBar: View {
    let value: Float
    var body: some View {
        let range = PointSegmenter.Parameters.toleranceRange
        let t = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass").font(.caption2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(Theme.accent).frame(width: max(6, g.size.width * t))
                }
            }
            .frame(width: 140, height: 6)
            Image(systemName: "plus.magnifyingglass").font(.caption2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

/// Short reference sheet, reachable from the editor menu.
struct GestureHelpView: View {
    var body: some View {
        List {
            Section("Selecting") {
                row("hand.tap.fill", "Hold on a piece", "Shows what will be selected. Release to add it.")
                row("lasso", "Draw a loop around a piece", "Everything inside that doesn't match the background is selected — best for busy stickers with text.")
                row("arrow.left.and.right", "Hold, then drag sideways", "Right selects more of the surrounding colour, left selects less.")
                row("arrow.up", "Hold, then swipe up", "Also take the shape wrapping it — a sticker's border around its artwork.")
                row("arrow.down", "Hold, then swipe down", "Cancel without selecting.")
            }
            Section("Editing") {
                row("hand.point.up.left.fill", "Hold on a selected piece", "Drill into the smaller piece under your finger and replace the large one.")
                row("hand.tap", "Tap a selected piece", "Remove it.")
                row("hand.tap.fill", "Hold a selected piece, swipe down", "Remove it.")
                row("arrow.uturn.backward", "Two-finger tap", "Undo.")
            }
            Section("Looking closer") {
                row("plus.magnifyingglass", "Pinch or double-tap", "Zoom. Detection re-runs on what's visible, so small stickers become selectable.")
                row("hand.draw", "Two-finger drag", "Move around while zoomed in.")
            }
        }
        .navigationTitle("Gestures")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ icon: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// All touch handling in one UIKit view so recognizers can arbitrate against each other reliably.
private struct EditorGestureView: UIViewRepresentable {
    var onHoldBegan: (CGPoint) -> Void
    var onHoldChanged: (CGSize) -> Void
    var onHoldEnded: () -> Void
    var onHoldCancelled: () -> Void
    var onTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onPinch: (CGFloat, UIGestureRecognizer.State) -> Void
    var onPan: (CGSize, UIGestureRecognizer.State) -> Void
    var onTwoFingerTap: () -> Void
    var onLasso: ([CGPoint], UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        let c = context.coordinator

        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.3
        // Movement beyond this *before* the 0.3 s elapses makes the hold fail, which is what lets a
        // drawing stroke become a lasso. Once the hold has begun, movement is unrestricted.
        hold.allowableMovement = 12
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let doubleTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let twoFingerTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.twoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let lasso = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.lasso(_:)))
        lasso.minimumNumberOfTouches = 1
        lasso.maximumNumberOfTouches = 1

        tap.require(toFail: doubleTap)
        lasso.require(toFail: hold)   // a hold that starts wins over drawing
        pinch.delegate = c
        pan.delegate = c

        [hold, tap, doubleTap, twoFingerTap, pinch, pan, lasso].forEach(v.addGestureRecognizer)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: EditorGestureView
        private var holdStart: CGPoint = .zero
        init(parent: EditorGestureView) { self.parent = parent }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                holdStart = p
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.onHoldBegan(p)
            case .changed:
                parent.onHoldChanged(CGSize(width: p.x - holdStart.x, height: p.y - holdStart.y))
            case .ended:
                parent.onHoldEnded()
            case .cancelled, .failed:
                parent.onHoldCancelled()
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) { parent.onTap(g.location(in: g.view)) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) { parent.onDoubleTap(g.location(in: g.view)) }
        @objc func twoFingerTap(_ g: UITapGestureRecognizer) { parent.onTwoFingerTap() }
        @objc func pinch(_ g: UIPinchGestureRecognizer) { parent.onPinch(g.scale, g.state) }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            parent.onPan(CGSize(width: t.x, height: t.y), g.state)
        }

        private var trail: [CGPoint] = []
        @objc func lasso(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began: trail = [p]
            case .changed: if let last = trail.last, hypot(p.x - last.x, p.y - last.y) > 2 { trail.append(p) }
            default: break
            }
            parent.onLasso(trail, g.state)
            if g.state == .ended || g.state == .cancelled || g.state == .failed { trail = [] }
        }

        // Pinch and pan together, so zooming with a drifting pinch also pans.
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            (a is UIPinchGestureRecognizer && b is UIPanGestureRecognizer) || (a is UIPanGestureRecognizer && b is UIPinchGestureRecognizer)
        }
    }
}

/// Tentative selection while the finger is down: the piece in its own colours, lifted a little,
/// with a white light sweeping around its edge (like the system's subject lift).
private struct LiftedPieceView: View {
    let visual: CaptureFlowModel.TentativeVisual
    let fitted: CGRect
    @State private var appeared = false

    var body: some View {
        let r = visual.rect
        let frame = CGRect(x: fitted.minX + r.minX * fitted.width, y: fitted.minY + r.minY * fitted.height,
                           width: r.width * fitted.width, height: r.height * fitted.height)
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 120).truncatingRemainder(dividingBy: 360))
            ZStack {
                Image(decorative: visual.cutout, scale: 1)
                    .resizable()
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                // Edge ring: a soft steady glow plus a brighter sweep travelling around it.
                Image(decorative: visual.outline, scale: 1)
                    .resizable()
                    .opacity(0.55)
                    .blur(radius: 1.5)
                AngularGradient(colors: [.white.opacity(0), .white, .white.opacity(0), .white.opacity(0), .white.opacity(0.7), .white.opacity(0)],
                                center: .center, angle: angle)
                    .mask(Image(decorative: visual.outline, scale: 1).resizable())
                    .blendMode(.plusLighter)
            }
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(appeared ? 1.03 : 1.0)
            .position(x: frame.midX, y: frame.midY)
        }
        .onAppear { withAnimation(.spring(duration: 0.3)) { appeared = true } }
        .transition(.opacity)
    }
}

/// One-shot "pop": the freshly lifted piece scales up with a white glow, then settles back and fades.
private struct PickPopView: View {
    let highlight: CaptureFlowModel.PickHighlight
    let fitted: CGRect

    private struct Pop { var scale: CGFloat = 1; var opacity: Double = 1; var glow: CGFloat = 0 }

    var body: some View {
        let r = highlight.rect
        let frame = CGRect(x: fitted.minX + r.minX * fitted.width, y: fitted.minY + r.minY * fitted.height,
                           width: r.width * fitted.width, height: r.height * fitted.height)
        Image(decorative: highlight.image, scale: 1)
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .keyframeAnimator(initialValue: Pop(), trigger: highlight.id) { view, pop in
                view
                    .shadow(color: .white.opacity(Double(pop.glow)), radius: 6)
                    .shadow(color: .white.opacity(Double(pop.glow) * 0.8), radius: 14)
                    .scaleEffect(pop.scale)
                    .opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.18, duration: 0.22, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(1.0, duration: 0.15)
                    LinearKeyframe(1.0, duration: 0.25)
                    LinearKeyframe(0.0, duration: 0.3)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 0.55)
                    LinearKeyframe(0.0, duration: 0.25)
                }
            }
            .position(x: frame.midX, y: frame.midY)
    }
}
