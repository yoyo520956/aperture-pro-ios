import SwiftUI

struct MotionShotView: View {
    @StateObject private var engine = MotionShotEngine()
    @State private var showResult: Bool = false
    @State private var resultImage: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 260, height: 320)

                VStack(spacing: 12) {
                    Image(systemName: "burst")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("频闪摄影")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("\(engine.frameCount) / \(engine.maxFrames) 帧")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.orange)

                    if engine.isCapturing {
                        ProgressView()
                            .tint(.orange)
                    }

                    if showResult, let img = resultImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            HStack(spacing: 12) {
                if !engine.isCapturing {
                    Button("开始拍摄") {
                        engine.startCapture()
                        showResult = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Button("合成") {
                        if let result = engine.stopCapture() {
                            resultImage = result
                            showResult = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("取消") {
                        engine.startCapture()
                        showResult = false
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 16) {
                Stepper("帧数: \(engine.maxFrames)", value: $engine.maxFrames, in: 2...16, step: 2)
                    .font(.caption)
                    .disabled(engine.isCapturing)
            }
        }
        .padding()
    }
}
