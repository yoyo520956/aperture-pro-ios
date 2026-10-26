// ARTracker.swift
// 面部追踪 AR 会话管理器
// iOS 16+ / Swift 5.9 + SwiftUI + ARKit

import ARKit
import SwiftUI

// MARK: - AR State

/// 可观察对象，持有 AR 追踪状态
@available(iOS 13.0, *)
class ARState: ObservableObject {
    /// 是否正在追踪人脸
    @Published var isTracking: Bool = false
    /// 当前人脸锚点（可为 nil）
    @Published var faceAnchor: ARFaceAnchor? = nil
    /// 最近错误信息
    @Published var errorMessage: String? = nil

    /// 切换追踪开关
    func toggleTracking(with session: ARSession) {
        isTracking.toggle()
        if isTracking {
            let config = ARFaceConfiguration()
            config.lightEstimationEnabled = true
            do {
                try session.run(config, options: [.resetTracking, .removeExistingAnchors])
                errorMessage = nil
            } catch {
                isTracking = false
                errorMessage = "启动 AR 追踪失败：\(error.localizedDescription)"
            }
        } else {
            session.pause()
        }
    }

    /// 更新锚点
    func updateAnchor(_ anchor: ARFaceAnchor) {
        faceAnchor = anchor
    }
}

// MARK: - AR Camera View

/// UIViewRepresentable：显示 ARKit 相机画面
@available(iOS 13.0, *)
struct ARCameraView: UIViewRepresentable {
    let arState: ARState
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.session.delegate = context.coordinator
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate {
        let parent: ARCameraView

        init(_ parent: ARCameraView) {
            self.parent = parent
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let anchor = frame.faceAnchor else { return }
            parent.arState.updateAnchor(anchor)
        }
    }
}

// MARK: - Tracking Overlay View

/// 面部追踪叠加层（UIViewRepresentable）
@available(iOS 13.0, *)
struct ARTrackingOverlayView: UIViewRepresentable {
    let arState: ARState
    let screenSize: CGSize

    func makeUIView(context: Context) -> ARTrackingOverlayUIView {
        ARTrackingOverlayUIView(screenSize: screenSize)
    }

    func updateUIView(_ uiView: ARTrackingOverlayUIView, context: Context) {
        uiView.arState = arState
        uiView.setNeedsDisplay()
    }
}

/// 绘制面部角点的 UIView
@available(iOS 13.0, *)
class ARTrackingOverlayUIView: UIView {
    var arState: ARState?

    init(screenSize: CGSize) {
        super.init(frame: .zero)
        self.backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: screenSize.width),
            heightAnchor.constraint(equalToConstant: screenSize.height)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let anchor = arState?.faceAnchor else { return }
        guard let mesh = anchor.mesh else { return }

        // 选取面部 4 个角点（indices 基于 ARKit 人脸网格）
        let points = extractFacePoints(mesh: mesh, viewport: rect.size)
        guard points.count == 4 else { return }

        let leftEye    = points[0]
        let rightEye   = points[1]
        let noseTip    = points[2]
        let mouthCenter = points[3]

        // 绘图上下文
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.blue.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)

        // 连线：左眼 - 右眼，鼻 - 左眼，鼻 - 右眼，左眼 - 嘴，右眼 - 嘴
        let lines: [(CGPoint, CGPoint)] = [
            (leftEye, rightEye),
            (leftEye, noseTip),
            (rightEye, noseTip),
            (leftEye, mouthCenter),
            (rightEye, mouthCenter)
        ]
        for (start, end) in lines {
            ctx.move(to: start)
            ctx.addLine(to: end)
        }
        ctx.strokePath()

        // 绘制圆点
        let dotRadius: CGFloat = 8.0
        for point in points {
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: point.x - dotRadius, y: point.y - dotRadius,
                                       width: dotRadius * 2, height: dotRadius * 2))
        }
    }

    /// 从 ARKit 网格提取 4 个关键顶点并映射到屏幕坐标
    private func extractFacePoints(mesh: ARMeshDescriptor, viewport: CGSize) -> [CGPoint] {
        // vertex indices 参考 ARKit 人脸网格约定（blendshape 顶点索引）
        // 左眼: index 63, 右眼: index 103, 鼻尖: index 23, 嘴中: index 47
        let faceIndices: [Int] = [63, 103, 23, 47]
        guard let vertices = mesh.vertices else { return [] }

        var points: [CGPoint] = []
        for idx in faceIndices {
            guard idx < vertices.count else { continue }
            let simdVec = vertices[idx]
            // 将世界坐标转换为 NDC 再映射到屏幕
            let x = (simdVec.x + 1.0) / 2.0 * viewport.width
            let y = (1.0 - (simdVec.y + 1.0) / 2.0) * viewport.height
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}

// MARK: - Public SwiftUI View

/// 主 AR 追踪视图（可嵌入相机界面）
///
/// 用法示例：
/// ```swift
/// let state = ARState()
/// ARTrackingView(arState: state)
/// ```
@available(iOS 13.0, *)
struct ARTrackingView: View {
    @StateObject private var arState: ARState
    let session: ARSession

    @State private var toggleOn = false
    @State private var overlaySize = CGSize(width: 390, height: 844)

    init(arState: ARState = ARState(), session: ARSession = ARSession()) {
        _arState = StateObject(wrappedValue: arState)
        self.session = session
    }

    var body: some View {
        ZStack {
            // AR 相机画面
            ARCameraView(arState: arState, session: session)
                .ignoresSafeArea()

            // 面部追踪叠加层
            ARTrackingOverlayView(arState: arState, screenSize: overlaySize)

            // 底部标签栏
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(arState.isTracking ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(arState.isTracking ? "面部追踪 — 追踪中" : "面部追踪 — 未检测到")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45))
                .cornerRadius(8)

                Spacer()
            }
            .padding(.bottom, 60)

            // 切换按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            toggleOn.toggle()
                            arState.toggleTracking(with: session)
                        }
                    } label: {
                        Text(toggleOn ? "停止追踪" : "开始追踪")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.75))
                            .cornerRadius(20)
                            .shadow(radius: 3)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                }
                Spacer()
            }
        }
        .onAppear {
            // 获取实际屏幕尺寸
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
               let screenSize = windowScene.windows.first?.bounds.size {
                overlaySize = screenSize
            }
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
}

// MARK: - Preview

#if DEBUG
@available(iOS 13.0, *)
struct ARTrackingView_Previews: PreviewProvider {
    static var previews: some View {
        ARTrackingView()
    }
}
#endif
