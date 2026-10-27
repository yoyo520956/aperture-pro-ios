import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var engine: CameraEngine

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.engine = engine
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if engine.isRunning {
            if let layer = uiView.previewLayer {
                layer.session = engine.session
            }
        }
    }
}

class CameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var engine: CameraEngine?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let engine {
            let layer = AVCaptureVideoPreviewLayer(session: engine.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            // 重建预览层前先清旧子层，避免层叠堆积
            for sub in layerLayout.sublayers ?? [] {
                sub.removeFromSuperlayer()
            }
            previewLayer = layer
            layerLayout.addSublayer(layer)
        }
    }

    private var layerLayout: CALayer = CALayer()
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if previewLayer == nil {
            layerLayout.frame = bounds
            layerLayout.masksToBounds = true
            layerLayout.addSublayer(previewLayer ?? CALayer())
            layerLayout.isHidden = true
        }
    }
}
