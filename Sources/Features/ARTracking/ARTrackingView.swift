// ARTrackingView.swift
// SwiftUI 面部追踪叠加层视图
// iOS 16+ / Swift 5.9
//
// 4 个角点由 ARFaceAnchor.mesh 顶点投影后按行带聚类估计（见 ARState.updateLandmarks），
// 不再是硬编码坐标；连线随脸移动

import SwiftUI
import ARKit
import Combine

// MARK: - Face Landmark View

/// 单个面部角点标注（圆点 + 描边 + 阴影）
@available(iOS 16.0, *)
struct FaceLandmarkDot: View {
    let position: CGPoint
    let label: String
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(
                isActive
                    ? Color.blue.opacity(0.85)
                    : Color.gray.opacity(0.4)
            )
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            )
            .position(position)
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
            .tooltip(text: label, position: position)
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
                .foregroundStyle(.white)
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
/// 角点坐标来源：ARState.landmarks（由 ARKit 人脸网格顶点投影估计），
/// 连线为 左眼—右眼、鼻↔双眼、双眼→嘴
@available(iOS 16.0, *)
struct ARTrackingOverlay: View {
    @ObservedObject var arState: ARState
    let session: ARSession
    let screenSize: CGSize

    var body: some View {
        ZStack {
            Color.clear
            landmarkLayer
            statusChip
            toggleButton
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    // MARK: 角点 + 连线

    @ViewBuilder
    private var landmarkLayer: some View {
        let ls = arState.landmarks
        if ls.count == 4 {
            FaceLine(start: ls[0].point, end: ls[1].point)
                .stroke(Color.blue.opacity(0.6), lineWidth: 2)
            FaceLine(start: ls[0].point, end: ls[2].point)
                .stroke(Color.blue.opacity(0.6), lineWidth: 2)
            FaceLine(start: ls[1].point, end: ls[2].point)
                .stroke(Color.blue.opacity(0.6), lineWidth: 2)
            FaceLine(start: ls[0].point, end: ls[3].point)
                .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
            FaceLine(start: ls[1].point, end: ls[3].point)
                .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)

            ForEach(0..<ls.count, id: \.self) { i in
                FaceLandmarkDot(position: ls[i].point,
                                label: ls[i].name,
                                isActive: arState.isTracking)
            }
        }
    }

    // MARK: 顶部状态栏

    private var statusChip: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(arState.isTracking ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
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
        }
    }

    private var statusText: String {
        if !arState.isTracking { return "面部追踪 — 已暂停" }
        return arState.landmarks.isEmpty ? "面部追踪 — 未检测到" : "面部追踪 — 追踪中"
    }

    // MARK: 底部切换按钮

    private var toggleButton: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) {
                    arState.toggleTracking(with: session)
                }
            } label: {
                Text(arState.isTracking ? "停止追踪" : "开始追踪")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
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

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
struct ARTrackingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ARTrackingOverlay(
            arState: ARState(),
            session: ARSession(),
            screenSize: CGSize(width: 390, height: 844)
        )
        .preferredColorScheme(.dark)
    }
}
#endif
