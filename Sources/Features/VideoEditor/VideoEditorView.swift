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
    @State private var pickerItem: PhotosPickerItem?
    @State private var assetURL: URL?
    @State private var speed: Float = 1.0
    @State private var muted: Bool = false
    @State private var filter: VideoFilter = .none
    @State private var exporting: Bool = false
    @State private var exportProgress: Double = 0
    @State private var message: String?
    @State private var multiMode: Bool = false
    @State private var segments: [SegRow] = []

    struct SegRow: Identifiable {
        let id = UUID()
        var url: URL
        var duration: Double
        var start: Double = 0
        var speed: Float = 1.0
        var filter: VideoFilter = .none
        var fade: Bool = false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                playerArea
                if multiMode && !segments.isEmpty {
                    multiList
                }
                statusViews
            }
            .navigationTitle("视频编辑")
            .onChange(of: pickerItem) { _, item in
                handlePicked(item)
            }
        }
        .toolbar(content: { editorToolbar })
    }

    // 拆分子表达式：避免单个 ViewBuilder 过大导致 type-check 超时
    @ViewBuilder
    private var playerArea: some View {
        if let url = assetURL {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .id(url)
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
    }

    @ViewBuilder
    private var statusViews: some View {
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

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if assetURL != nil {
                Button(multiMode ? "单段" : "多段") {
                    multiMode.toggle()
                    if multiMode && segments.isEmpty {
                        seedSegments()
                    }
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if assetURL == nil {
                PhotosPicker("选择视频", selection: $pickerItem, matching: .videos)
            }
        }
    }

    private func handlePicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vedit_src_\(UUID().uuidString).mp4")
                try? data.write(to: url)
                assetURL = url
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
        exporting = true
        exportProgress = 0
        Task {
            let ok: Bool
            if multiMode && segments.count >= 2 {
                let ms = segments.map { seg -> VideoExporter.MultiSegment in
                    VideoExporter.MultiSegment(
                        url: seg.url,
                        start: seg.start,
                        duration: seg.duration,
                        speed: seg.speed,
                        filter: seg.filter,
                        mutedSegment: muted,
                        fade: seg.fade
                    )
                }
                ok = await VideoExporter.exportMulti(ms, muted: muted) { p in
                    exportProgress = p
                }
            } else {
                guard let url = assetURL else {
                    exporting = false
                    return
                }
                ok = await VideoExporter.export(
                    source: url, speed: speed, muted: muted, filter: filter
                ) { p in
                    exportProgress = p
                }
            }
            exporting = false
            message = ok ? "已导出并保存到相册" : "导出失败，请重试"
        }
    }

    // MARK: - 多段时间轴

    private func seedSegments() {
        guard let url = assetURL else { return }
        segments = [SegRow(url: url, duration: 10)]
    }

    private var multiList: some View {
        VStack(spacing: 10) {
            HStack {
                Text("时间轴 · \(segments.count) 段")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker("加片段", selection: $addPicker, matching: .videos)
            }
            ForEach($segments) { $seg in
                segRow(seg: $seg)
            }
        }
        .padding(.horizontal)
        .onChange(of: addPicker) { _, items in
            Task { await addSegments(items) }
        }
    }

    @State private var addPicker: [PhotosPickerItem] = []

    private func addSegments(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vedit_seg_\(UUID().uuidString).mp4")
                try? data.write(to: url)
                segments.append(SegRow(url: url, duration: 10))
            }
        }
        addPicker = []
    }

    private func segRow(seg: Binding<SegRow>) -> some View {
        VStack(spacing: 8) {
            segRowHead(seg: seg)
            segRowTails(seg: seg)
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func segRowHead(seg: Binding<SegRow>) -> some View {
        HStack(spacing: 8) {
            if let idx = segments.firstIndex(where: { $0.id == seg.wrappedValue.id }) {
                    Text("#\(idx + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                ForEach(VideoFilter.allCases.prefix(3), id: \.self) { f in
                    chip(f.rawValue, selected: seg.wrappedValue.filter == f) {
                        seg.wrappedValue.filter = f
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    segments.removeAll { $0.id == seg.wrappedValue.id }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }

    private func segRowTails(seg: Binding<SegRow>) -> some View {
        HStack(spacing: 8) {
            chip(String(format: "%.1f×", seg.wrappedValue.speed),
                     selected: seg.wrappedValue.speed == 1.0) {
                    let order: [Float] = [1.0, 1.5, 2.0]
                    let cur = order.firstIndex { abs($0 - seg.wrappedValue.speed) < 0.1 } ?? 0
                    seg.wrappedValue.speed = order[(cur + 1) % order.count]
                }
                chip("首尾交叉 0.5s", selected: seg.wrappedValue.fade) {
                    seg.wrappedValue.fade.toggle()
                }
                Toggle("静音", isOn: Binding(
                    get: { muted },
                    set: { muted = $0 }
                ))
                .font(.system(size: 11))
                .toggleStyle(.button)
            .labelsHidden()
        }
    }
}
