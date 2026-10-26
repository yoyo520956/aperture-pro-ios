// ARTrackingView.swift
// SwiftUI 面部追踪叠加层视图
// iOS 16+ / Swift 5.9
//
// 显示 4 个蓝色圆点标注面部关键位置，并通过连线建立面部结构
// 支持开关追踪，配有中文状态标签

import SwiftUI
import ARKit

// MARK: - Face Landmark View

/// 单个面部角点标注（蓝色圆点 + 半透明）
@available(iOS 16.0, *)
struct FaceLandmarkDot: View {
    let position: CGPoint
    let label: String
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(
                isActive
                    ? Color.systemBlue.opacity(0.85)
                    : Color.gray.opacity(0.4)
            )
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            )
            .position(position)
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
            .tooltip(text: "\(label)", position: position)
    }
}

// MARK: - Face Line

/// 面部角点之间的连线
@available(iOS 16.0, *)
struct FaceLine: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

// MARK: - Tooltip Modifier

/// 简单的 tooltip 修饰符（标签浮在圆点上方）
@available(iOS 16.0, *)
extension View {
    func tooltip(text: String, position: CGPoint) -> some View {
        self.modifier(FaceTooltip(text: text, position: position))
    }
}

@available(iOS 16.0, *)
struct FaceTooltip: ViewModifier {
    let text: String
    let position: CGPoint

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65))
                .cornerRadius(4)
                .offset(y: -16)
                .position(x: position.x, y: position.y)
        }
    }
}

// MARK: - Main AR Tracking Overlay

/// 面部追踪叠加层主视图
///
/// 接收 `ARState` 实例，在屏幕上渲染：
/// - 5 条连线（左眼-右眼、鼻↔双眼、双眼→嘴）
/// - 4 个蓝色圆点（左眼、右眼、鼻尖、嘴中）
/// - 顶部状态标签
/// - 底部切换按钮
@available(iOS 16.0, *)
struct ARTrackingOverlay: View {
    let arState: ARState
    let screenSize: CGSize

    // 4 个面部角点（在屏幕坐标系中）
    @State private var leftEye    = CGPoint(x: 130, y: 280)
    @State private var rightEye   = CGPoint(x: 260, y: 280)
    @State private var noseTip    = CGPoint(x: 195, y: 370)
    @State private var mouthCenter = CGPoint(x: 195, y: 460)

    @State private var isTracking = false

    var body: some View {
        ZStack {
            Color.clear

            // 连线层
            FaceLine(start: leftEye, end: rightEye)
                .stroke(Color.systemBlue.opacity(0.6), lineWidth: 2)
            FaceLine(start: leftEye, end: noseTip)
                .stroke(Color.systemBlue.opacity(0.6), lineWidth: 2)
            FaceLine(start: rightEye, end: noseTip)
                .stroke(Color.systemBlue.opacity(0.6), lineWidth: 2)
            FaceLine(start: leftEye, end: mouthCenter)
                .stroke(Color.systemBlue.opacity(0.5), lineWidth: 1.5)
            FaceLine(start: rightEye, end: mouthCenter)
                .stroke(Color.systemBlue.opacity(0.5), lineWidth: 1.5)

            // 4 个角点标注
            FaceLandmarkDot(position: leftEye,    label: "左眼", isActive: isTracking)
            FaceLandmarkDot(position: rightEye,   label: "右眼", isActive: isTracking)
            FaceLandmarkDot(position: noseTip,    label: "鼻尖", isActive: isTracking)
            FaceLandmarkDot(position: mouthCenter, label: "嘴",  isActive: isTracking)

            // 顶部状态栏
            VStack(spacing: 0) {
                HStack {
                    Capsule(style: .circular)
                        .fill(isTracking ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isTracking ? "面部追踪 — 追踪中" : "面部追踪 — 未检测到")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.4))
                .cornerRadius(20)
                .padding(.top, 60)
                .padding(.horizontal, 16)

                Spacer()

                // 切换按钮
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isTracking.toggle()
                        }
                    } label: {
                        Text(isTracking ? "停止追踪" : "开始追踪")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(24)
                            .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .onAppear {
            // 从 ARState 同步追踪状态
            isTracking = arState.isTracking
        }
        .onChange(of: arState.isTracking) { newValue in
            isTracking = newValue
        }
        .onChange(of: arState.faceAnchor) { _ in
            // 有锚点时刷新角点位置（此处使用模拟坐标，实际可从 mesh 计算）
            updateLandmarkPositions()
        }
    }

    // MARK: - Landmark Position Update

    /// 根据当前 AR 锚点更新 4 个角点屏幕坐标
    /// 实际实现应从 ARFaceAnchor.mesh.vertices 计算，此处使用占位坐标
    private func updateLandmarkPositions() {
        // TODO: 接入真实 mesh 顶点坐标映射
        // 当前使用居中假想坐标，等待 ARTracker.swift 提供数据回调
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
struct ARTrackingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ARTrackingOverlay(
            arState: ARState(),
            screenSize: CGSize(width: 390, height: 844)
        )
        .preferredColorScheme(.dark)
    }
}
#endif
