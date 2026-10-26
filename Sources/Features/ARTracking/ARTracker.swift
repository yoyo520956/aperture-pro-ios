// ARTracker.swift
// 面部追踪 AR 会话管理器
// iOS 16+ / Swift 5.9 + SwiftUI + ARKit

import ARKit
import QuartzCore
import SwiftUI

// MARK: - Face Landmark

/// 面部语义角点（由人脸网格投影点云按行带聚类估计，不是硬编码坐标）
@available(iOS 16.0, *)
struct FaceLandmark {
    let name: String
    let point: CGPoint
}

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

    /// 弱引用 ARView，顶点投影用（模型空间 → 视图坐标）
    weak var arView: ARView?

    /// 面部语义角点（视图坐标）
    @Published var landmarks: [FaceLandmark] = []

    /// 上次角点更新时间（节流 ~20Hz，避免每帧刷 SwiftUI）
    private var lastLandmarkUpdate: CFTimeInterval = 0

    /// 由 ARFaceAnchor.mesh 顶点投影点云估计 4 个语义角点
    /// 采样网格顶点 → ARView.project 投到视图坐标 → 按包围盒相对高度切行带聚类
    func updateLandmarks(for anchor: ARFaceAnchor) {
        guard let view = arView else { return }
        guard let mesh = anchor.mesh, let verts = mesh.vertices, verts.count >= 512 else {
            landmarks = []
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastLandmarkUpdate > 0.05 else { return }
        lastLandmarkUpdate = now

        let step = max(1, verts.count / 160)
        var pts: [CGPoint] = []
        pts.reserveCapacity(160)
        for i in Swift.stride(from: 0, to: verts.count, by: step) {
            let world = anchor.transform.act(verts[i])
            pts.append(view.project(world, cameraTransform: .identity, relativeTo: .identity))
        }
        guard pts.count > 24 else { return }

        let minY = pts.map { $0.y }.min()!
        let maxY = pts.map { $0.y }.max()!
        let h = max(maxY - minY, 1)

        // 取包围盒相对高度 rel 处、半高 half 的行带内点
        func band(_ rel: Double, _ half: Double) -> [CGPoint] {
            let y0 = minY + h * rel
            return pts.filter { abs($0.y - y0) <= h * half }
        }

        // 眼行：包围盒上部，按水平中位数把点云劈成左右两簇（以屏幕左右为准）
        var result: [FaceLandmark] = []
        if let eyes = splitEyes(band(0.30, 0.07)) {
            result.append(FaceLandmark(name: "左眼", point: eyes.0))
            result.append(FaceLandmark(name: "右眼", point: eyes.1))
        }
        // 鼻：中部行带水平中位
        if let nose = meanOf(band(0.52, 0.06)) {
            result.append(FaceLandmark(name: "鼻尖", point: nose))
        }
        // 嘴：下部行带水平中位
        if let mouth = meanOf(band(0.74, 0.06)) {
            result.append(FaceLandmark(name: "嘴", point: mouth))
        }

        guard result.count == 4 else { return }
        landmarks = result
    }

    /// 按水平中位数把眼行点云劈成左右两簇，各取质心
    private func splitEyes(_ p: [CGPoint]) -> (CGPoint, CGPoint)? {
        guard p.count >= 6 else { return nil }
        guard let mx = medianOf(p.map { Double($0.x) }) else { return nil }
        let left = p.filter { $0.x < mx }
        let right = p.filter { $0.x > mx }
        guard left.count >= 3, right.count >= 3 else { return nil }
        return (meanOf(left)!, meanOf(right)!)
    }

    private func meanOf(_ p: [CGPoint]) -> CGPoint? {
        guard !p.isEmpty else { return nil }
        let x = p.reduce(0.0) { $0 + $1.x } / Double(p.count)
        let y = p.reduce(0.0) { $0 + $1.y } / Double(p.count)
        return CGPoint(x: x, y: y)
    }

    private func medianOf(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s[s.count / 2]
    }

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
        arState.arView = arView
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
            let arState = parent.arState
            // ARSession 回调在会话队列，@Published 必须回主线程
            DispatchQueue.main.async {
                arState.updateAnchor(anchor)
                arState.updateLandmarks(for: anchor)
            }
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
        guard let arState, let anchor = arState.faceAnchor, let view = arState.arView else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // 面部中心：ARKit 人脸坐标系原点（鼻梁附近）→ 世界系 → 视图坐标
        let center = view.project(
            anchor.transform.act(simd_float3(0, 0, 0)),
            cameraTransform: .identity,
            relativeTo: .identity
        )
        ctx.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.5)
        let arm: CGFloat = 14
        ctx.move(to: CGPoint(x: center.x - arm, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + arm, y: center.y))
        ctx.move(to: CGPoint(x: center.x, y: center.y - arm))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + arm))
        ctx.strokePath()
        ctx.setFillColor(UIColor.systemTeal.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))

        // 面部轮廓：均匀采样网格顶点，模型空间 → 世界系 → 视图坐标投影，低透明折线
        guard let mesh = anchor.mesh, let vertices = mesh.vertices, vertices.count > 128 else { return }
        let sampleCount = 96
        let step = max(1, vertices.count / sampleCount)
        var pts: [CGPoint] = []
        for i in Swift.stride(from: 0, to: vertices.count, by: step) {
            let worldPoint = anchor.transform.act(vertices[i])
            pts.append(view.project(worldPoint,
                                    cameraTransform: .identity,
                                    relativeTo: .identity))
        }
        guard pts.count > 1 else { return }
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1.2)
        for i in 0..<(pts.count - 1) {
            ctx.move(to: pts[i])
            ctx.addLine(to: pts[i + 1])
        }
        ctx.strokePath()
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
