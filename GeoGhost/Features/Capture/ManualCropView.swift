import SwiftUI

/// Fallback editor: drag a rectangle (and its corners) around the piece.
struct ManualCropView: View {
    let image: CGImage
    let canGoBack: Bool
    let onDone: (CGRect) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    /// Normalized crop rect (origin top-left).
    @State private var rect = CGRect(x: 0.15, y: 0.25, width: 0.7, height: 0.5)
    @State private var dragStart: CGRect?

    private let handleSize: CGFloat = 28
    private let minSize: CGFloat = 0.05

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: canGoBack ? onBack : onCancel) {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
                Spacer()
                Text("Drag to frame the piece").font(.subheadline.weight(.semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)

            GeometryReader { geo in
                let fitted = fittedRect(in: geo.size)
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                    // Dim outside the crop.
                    let px = pixelRect(rect, in: fitted)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        p.addRect(px)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    Rectangle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: px.width, height: px.height)
                        .position(x: px.midX, y: px.midY)
                        .contentShape(Rectangle())
                        .gesture(moveGesture(in: fitted))

                    ForEach(Corner.allCases, id: \.self) { corner in
                        Circle()
                            .fill(.white)
                            .frame(width: handleSize, height: handleSize)
                            .shadow(radius: 3)
                            .position(corner.point(in: px))
                            .gesture(cornerGesture(corner, in: fitted))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            Button { onDone(rect) } label: { Label("Use this crop", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16).padding(.vertical, 16)
        }
        .background(Color.black)
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        func point(in r: CGRect) -> CGPoint {
            switch self {
            case .topLeft: CGPoint(x: r.minX, y: r.minY)
            case .topRight: CGPoint(x: r.maxX, y: r.minY)
            case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
            case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
            }
        }
    }

    private func moveGesture(in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if dragStart == nil { dragStart = rect }
                guard let start = dragStart else { return }
                var r = start.offsetBy(dx: v.translation.width / fitted.width, dy: v.translation.height / fitted.height)
                r.origin.x = min(max(0, r.origin.x), 1 - r.width)
                r.origin.y = min(max(0, r.origin.y), 1 - r.height)
                rect = r
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Corner, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if dragStart == nil { dragStart = rect }
                guard let s = dragStart else { return }
                let dx = v.translation.width / fitted.width, dy = v.translation.height / fitted.height
                var minX = s.minX, minY = s.minY, maxX = s.maxX, maxY = s.maxY
                switch corner {
                case .topLeft: minX += dx; minY += dy
                case .topRight: maxX += dx; minY += dy
                case .bottomLeft: minX += dx; maxY += dy
                case .bottomRight: maxX += dx; maxY += dy
                }
                minX = max(0, min(minX, maxX - minSize)); minY = max(0, min(minY, maxY - minSize))
                maxX = min(1, max(maxX, minX + minSize)); maxY = min(1, max(maxY, minY + minSize))
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func fittedRect(in container: CGSize) -> CGRect {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(container.width / size.width, container.height / size.height)
        let s = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (container.width - s.width) / 2, y: (container.height - s.height) / 2, width: s.width, height: s.height)
    }

    private func pixelRect(_ n: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + n.minX * fitted.width, y: fitted.minY + n.minY * fitted.height, width: n.width * fitted.width, height: n.height * fitted.height)
    }
}
