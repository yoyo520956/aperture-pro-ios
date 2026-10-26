import SwiftUI
import ARKit

/// AR 面部追踪宿主视图（ARCameraView + 角点叠加层）
@available(iOS 16.0, *)
struct ARFaceView: View {
    @StateObject private var arState = ARState()
    @State private var session: ARSession = ARSession()

    var body: some View {
        ZStack {
            ARCameraView(arState: arState, session: session)
                .ignoresSafeArea()
            ARTrackingOverlay(arState: arState, screenSize: CGSize(width: 390, height: 844))
                .ignoresSafeArea()
        }
        .onAppear {
            session.run()
        }
        .onDisappear {
            session.pause()
        }
    }
}
