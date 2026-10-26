import SwiftUI
import AVFoundation

class VideoEditor: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var sourceURL: URL?
    @Published var resultURL: URL?
    @Published var selectedTool: VideoTool = .trim
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0

    func loadVideo(_ url: URL) {
        sourceURL = url
        resultURL = nil
        let asset = AVURLAsset(url: url)
        DispatchQueue.global(qos: .userInitiated).async {
            let duration = CMTimeGetSeconds(asset.duration)
            DispatchQueue.main.async {
                self.trimEnd = duration
            }
        }
    }

    func exportTrimmed() {
        guard let source = sourceURL else { return }
        isProcessing = true
        progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: source)
            let export = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHEVCHighestQuality
            )
            let outURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("trimmed_\(Int(Date().timeIntervalSince1970)).mov")
            export.outputURL = outURL
            export.outputFileType = .mov
            export.trimRange = CMTimeRange(
                start: CMTime(seconds: self.trimStart, preferredTimescale: 600),
                end: CMTime(seconds: self.trimEnd, preferredTimescale: 600)
            )
            export.shouldOptimizeForNetworkUse = true
            export.exportAsynchronously {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    if let err = export.error {
                        print("导出失败: \(err)")
                    } else {
                        self.resultURL = outURL
                        self.progress = 1.0
                    }
                }
            }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.progress = export.progress
                if export.progress >= 1.0 { timer.invalidate() }
            }
        }
    }

    func exportMuted() {
        guard let source = sourceURL else { return }
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: source)
            let export = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHEVCHighestQuality
            )
            let outURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("muted_\(Int(Date().timeIntervalSince1970)).mov")
            export.outputURL = outURL
            export.outputFileType = .mov
            export.exportAsynchronously {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.resultURL = outURL
                    self.progress = 1.0
                }
            }
        }
    }

    func reset() {
        sourceURL = nil
        resultURL = nil
        progress = 0
        trimStart = 0
        trimEnd = 0
    }
}

enum VideoTool: String, CaseIterable, Codable {
    case trim = "裁剪"
    case compress = "压缩"
    case mute = "静音"
    case rotate = "旋转"
}

struct VideoEditorView: View {
    @StateObject private var editor = VideoEditor()
    @State private var showVideoPicker: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let url = editor.sourceURL {
                    VideoPlayerView(url: url)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    toolSelector
                    if editor.selectedTool == .trim {
                        trimControls
                    }
                    HStack(spacing: 12) {
                        Button("导出") {
                            switch editor.selectedTool {
                            case .trim: editor.exportTrimmed()
                            case .mute: editor.exportMuted()
                            default: break
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editor.isProcessing)

                        if let result = editor.resultURL {
                            Button("分享") { }
                                .buttonStyle(.bordered)
                        }
                    }
                    if editor.isProcessing {
                        ProgressView(value: editor.progress)
                            .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.system(size: 56))
                            .foregroundStyle(.gray)
                        Text("选择一段视频开始编辑")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button("选择视频") { showVideoPicker = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .navigationTitle("视频编辑")
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerView { url in
                    editor.loadVideo(url)
                }
            }
        }
    }

    private var toolSelector: some View {
        HStack(spacing: 8) {
            ForEach(VideoTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
        }
        .padding(.horizontal)
    }

    private func toolButton(_ tool: VideoTool) -> some View {
        Group {
            if editor.selectedTool == tool {
                Button(tool.rawValue) {
                    editor.selectedTool = tool
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(tool.rawValue) {
                    editor.selectedTool = tool
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.system(size: 13))
    }

    private var trimControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(String(format: "起点: %.1fs", editor.trimStart))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "终点: %.1fs", editor.trimEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $editor.trimStart,
                   in: 0...max(editor.trimEnd - 0.5, 0.1),
                   step: 0.1)
                .tint(.blue)
            Slider(value: $editor.trimEnd,
                   in: min(editor.trimStart + 0.5, 999)...999,
                   step: 0.1)
                .tint(.orange)
        }
        .padding(.horizontal)
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> AVPlayerLayer {
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        let player = AVPlayer(url: url)
        playerLayer.player = player
        return playerLayer
    }

    func updateUIView(_ playerLayer: AVPlayerLayer, context: _ Context) {
    }
}

struct VideoPickerView: View {
    var onPick: (URL) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.gray)
                Text("视频选择功能需要视频库权限")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("请从相册选择视频文件")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
        .presentationDetents([.medium])
    }
}
