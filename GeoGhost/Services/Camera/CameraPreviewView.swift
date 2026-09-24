import AVFoundation
import SwiftUI

/// Live camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.onTap = onTap
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onTap = onTap
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            let p = g.location(in: self)
            onTap?(previewLayer.captureDevicePointConverted(fromLayerPoint: p))
        }
    }
}
