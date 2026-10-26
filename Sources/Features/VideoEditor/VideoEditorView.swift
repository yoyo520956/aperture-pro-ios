import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import CoreImage
import Photos

enum VideoFilter: String, CaseIterable, Identifiable {
    case none = "原片"
    case sepia = "复古"
    case mono = "黑白"
    case warm = "暖调"
    case cool = "冷调"
    var id: String { rawValue }

    var ciFilter: String? {
        switch self {
        case .none: return nil
        case .sepia: return "CISepiaTone"
        case .mono: return "CIColorMonochrome"
        case .warm, .cool: return "CITemperatureAndTint"
        }
    }
}

struct VideoEditorView: View {
    @State private var pickerItem: PHPickerItem?
    @State private var assetURL: URL?
    @State private var speed: Float = 1.0
    @State private var muted: Bool = false
    @State private var filter: VideoFilter = .none
    @State private var exporting: Bool = false
    @State private var exportProgress: Double = 0
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if assetURL != nil {
                    VideoPlayer(player: AVPlayer(url: assetURL!))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .id(assetURL)
                    controlGrid
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.system(size: 56))
                            .foregroundStyle(.gray)
                        Text("选择一段视频开始编辑")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.24, green: 0.36, blue: 0.42))
                }
                if exporting {
                    ProgressView(value: exportProgress)
                        .padding(.horizontal, 40)
                }
            }
            .navigationTitle("视频编辑")
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let dir = FileManager.default.temporaryDirectory
                        let url = dir.appendingPathComponent("vedit_src_\(UUID().uuidString).mp4")
                        try? data.write(to: url)
                        assetURL = url
                    }
                }
            }
        }
        .toolbar {
            if assetURL == nil {
                PhotosPicker("选择视频", selection: $pickerItem, matching: .movie)
            }
        }
    }

    private var controlGrid: some View {
        VStack(spacing: 14) {
            rowLabel("倍速", value: String(format: "%.1f×", speed))
            HStack(spacing: 10) {
                ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { s in
                    chip(s == speed ? String(format: "%.1f×", s) : String(format: "%.1f×", s),
                         selected: s == speed) { speed = s }
                }
            }
            HStack(spacing: 10) {
                Toggle("静音", isOn: $muted)
                    .font(.system(size: 13))
                Spacer()
            }
            rowLabel("滤镜", value: filter.rawValue)
            HStack(spacing: 8) {
                ForEach(VideoFilter.allCases) { f in
                    chip(f.rawValue, selected: filter == f) { filter = f }
                }
            }
            Button {
                exportClip()
            } label: {
                Label("导出并保存", systemImage: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(exporting)
        }
        .padding(.horizontal)
    }

    private func rowLabel(_ t: String, value: String) -> some View {
        HStack {
            Text(t).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium))
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(label) { action() }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(selected ? Color(red: 0.24, green: 0.36, blue: 0.42) : Color.gray.opacity(0.12)))
            .foregroundStyle(selected ? .white : .primary)
    }

    // MARK: - 导出

    private func exportClip() {
        guard let url = assetURL else { return }
        exporting = true
        exportProgress = 0
        Task {
            let ok = await VideoExporter.export(
                source: url, speed: speed, muted: muted, filter: filter
            ) { p in
                exportProgress = p
            }
            exporting = false
            message = ok ? "已导出并保存到相册" : "导出失败，请重试"
        }
    }
}
