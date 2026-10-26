import SwiftUI

enum VideoTool: String, CaseIterable, Codable {
    case trim = "裁剪"
    case compress = "压缩"
    case mute = "静音"
    case rotate = "旋转"
}

struct VideoEditorView: View {
    @State private var selectedTool: VideoTool = .trim
    @State private var showPicker: Bool = false
    @State private var loadedVideo: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if loadedVideo {
                    VStack(spacing: 12) {
                        Image(systemName: "video")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("视频已加载")
                            .font(.headline)
                        toolSelector
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.system(size: 56))
                            .foregroundStyle(.gray)
                        Text("选择一段视频开始编辑")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button("选择视频") { showPicker = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .navigationTitle("视频编辑")
            .sheet(isPresented: $showPicker) {
                VStack(spacing: 12) {
                    Text("视频选择功能需要视频库权限")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("确定") {
                        loadedVideo = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 200)
                .presentationDetents([.medium])
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
            if selectedTool == tool {
                Button(tool.rawValue) {
                    selectedTool = tool
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 13))
            } else {
                Button(tool.rawValue) {
                    selectedTool = tool
                }
                .buttonStyle(.bordered)
                .font(.system(size: 13))
            }
        }
    }
}
