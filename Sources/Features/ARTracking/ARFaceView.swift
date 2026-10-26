import SwiftUI
import ARKit

/// AR 面部追踪宿主视图（ARCameraView + 角点叠加层）
/// 用 ARFaceConfiguration 启动，否则 frame.faceAnchor 永远为空
@available(iOS 16.0, *)
struct ARFaceView: View {
    @StateObject private var arState = ARState()
    @State private var session: ARSession = ARSession()
    @State private var overlaySize = CGSize(width: 390, height: 844)

    var body: some View {
        ZStack {
            ARCameraView(arState: arState, session: session)
                .ignoresSafeArea()
            ARTrackingOverlay(arState: arState, session: session, screenSize: overlaySize)
                .ignoresSafeArea()
        }
        .onAppear {
            runFaceTracking()
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
               let size = scene.windows.first?.bounds.size {
                overlaySize = size
            }
        }
        .onDisappear {
            session.pause()
        }
        .alert("AR 错误", isPresented: Binding(
            get: { arState.errorMessage != nil },
            set: { if !$0 { arState.errorMessage = nil } }
        )) {
            Button("确定") {}
        } message: {
            Text(arState.errorMessage ?? "")
        }
    }

    private func runFaceTracking() {
        let config = ARFaceConfiguration()
        config.lightEstimationEnabled = true
        do {
            try session.run(config, options: [.resetTracking, .removeExistingAnchors])
            arState.isTracking = true
            arState.errorMessage = nil
        } catch {
            arState.isTracking = false
            arState.errorMessage = "启动 AR 追踪失败：\(error.localizedDescription)"
        }
    }
}
