import SwiftUI

/// 全景模式覆盖层：横扫取景 + 实时进度 + 一键拼接
struct PanoramaView: View {
    @ObservedObject var engine: CameraEngine
    @State private var stitched: Data?

    var body: some View {
        VStack {
            Spacer()
            if let stitched {
                HStack(spacing: CNTheme.sp16) {
                    Button {
                        stitched = nil
                    } label: {
                        VStack(spacing: CNTheme.sp4) {
                            Image(systemName: "xmark")
                            Text("重扫")
                        }
                        .font(CNTheme.f12)
                    }
                    .frame(width: 64, height: 64)

                    Button {
                        engine.onPhotoCaptured?(stitched)
                        stitched = nil
                    } label: {
                        VStack(spacing: CNTheme.sp4) {
                            Image(systemName: "checkmark")
                            Text("保存")
                        }
                        .font(CNTheme.f12)
                    }
                    .frame(width: 64, height: 64)
                    .tint(Color(CNTheme.cinnabar))
                }
            } else {
                progressCard
                HStack(spacing: CNTheme.sp24) {
                    Button {
                        engine.panoramaEngine.reset()
                    } label: {
                        Label("清空", systemImage: "trash")
                            .font(CNTheme.f14)
                    }
                    Button {
                        stitched = engine.panoramaEngine.stitch()
                    } label: {
                        Label("拼接全景", systemImage: "arrow.left.and.right")
                            .font(CNTheme.f14)
                            .fontWeight(.semibold)
                    }
                    .tint(engine.panoramaEngine.isCollecting ? Color(CNTheme.indigo) : Color(CNTheme.inkFaint))
                }
                .padding(.bottom, CNTheme.sp24)
            }
        }
        .padding(.vertical, CNTheme.sp16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.4))
    }

    private var progressCard: some View {
        VStack(spacing: CNTheme.sp8) {
            HStack(spacing: CNTheme.sp8) {
                Circle()
                    .fill(engine.panoramaEngine.isCollecting ? Color(CNTheme.indigo) : Color(CNTheme.inkFaint))
                    .frame(width: 10, height: 10)
                Text(engine.panoramaEngine.isCollecting ? "横扫手机，取景中" : "请横扫手机")
                    .font(CNTheme.f15)
                    .foregroundStyle(Color(CNTheme.ink))
            }
            ProgressView(value: Double(engine.panoramaEngine.capturedCount),
                        total: Double(engine.panoramaEngine.targetCount))
                .tint(Color(CNTheme.indigo))
                .padding(.horizontal, CNTheme.sp32)
            Text("\(engine.panoramaEngine.capturedCount) / \(engine.panoramaEngine.targetCount)")
                .font(CNTheme.f10)
                .foregroundStyle(Color(CNTheme.inkFaint))
        }
        .padding(CNTheme.sp16)
        .frame(maxWidth: .infinity)
        .background(CNTheme.card())
    }
}
