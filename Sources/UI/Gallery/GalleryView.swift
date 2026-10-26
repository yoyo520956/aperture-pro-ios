import SwiftUI
import AVFoundation
import AVKit
import Photos

// MARK: - 相册（本机 + 系统 + 长图拼接 + 中式皮）

struct GalleryView: View {
    @StateObject private var store = MediaStore()
    @State private var tab: GalleryTab = .mine
    @State private var selecting: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var systemItems: [PHLibraryService.SystemPhoto] = []
    @State private var detailItem: MediaItem?
    @State private var detailSystem: PHLibraryService.SystemPhoto?

    enum GalleryTab: String, CaseIterable {
        case mine = "本机"
        case system = "系统"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("相册", selection: $tab) {
                    ForEach(GalleryTab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(CNTheme.sp12)
                .padding(.bottom, CNTheme.sp8)

                if tab == .mine {
                    mineGrid
                } else {
                    systemGrid
                }

                if tab == .mine && selecting {
                    stitchBar
                }
            }
            .background(CNTheme.pageBackground())
            .navigationTitle("相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tab == .mine {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? "完成" : "选择") {
                            selecting.toggle()
                            selectedIDs = []
                        }
                        .tint(Color(CNTheme.indigo))
                    }
                }
            }
            .sheet(item: $detailItem) { item in
                MediaDetailView(item: item)
            }
            .sheet(item: $detailSystem) { sp in
                SystemDetailSheet(photo: sp)
            }
        }
        .onAppear {
            store.load()
            loadSystem()
        }
    }

    // MARK: 本机

    private var mineGrid: some View {
        ScrollView {
            LazyVGrid(columns: galleryColumns, spacing: 3) {
                ForEach(store.items) { item in
                    MediaCell(
                        item: item,
                        selected: selectedIDs.contains(item.id),
                        isSelecting: selecting
                    ) {
                        if selecting {
                            toggleSelect(item.id)
                        } else {
                            detailItem = item
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            if store.items.isEmpty {
                emptyState
            }
        }
    }

    private var galleryColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ]
    }

    private var emptyState: some View {
        VStack(spacing: CNTheme.sp8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color(CNTheme.inkFaint))
            Text("暂无媒体")
                .font(CNTheme.f17)
                .foregroundStyle(Color(CNTheme.ink))
            Text("拍一张，或从系统相册取回")
                .font(CNTheme.f12)
                .foregroundStyle(Color(CNTheme.inkFaint))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func toggleSelect(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private var stitchBar: some View {
        HStack(spacing: CNTheme.sp16) {
            Text("已选 \(selectedIDs.count)")
                .font(CNTheme.f14)
                .foregroundStyle(Color(CNTheme.inkSub))
            Spacer()
            Button {
                stitchSelected()
            } label: {
                Label("拼长图", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    .font(CNTheme.f14)
                    .fontWeight(.medium)
            }
            .tint(selectedIDs.count >= 2 ? Color(CNTheme.cinnabar) : Color(CNTheme.inkFaint))
            .disabled(selectedIDs.count < 2)
        }
        .padding(CNTheme.sp12)
        .background(CNTheme.card())
    }

    private func stitchSelected() {
        let datas = store.items
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.date < $1.date }
            .compactMap {
                let url = CameraEngine.mediaDir.appendingPathComponent($0.filename)
                return try? Data(contentsOf: url)
            }
        guard let longData = LongImageStitcher.stitchJPEGs(datas), datas.count >= 2 else {
            return
        }
        let name = "stitch_\(Int(Date().timeIntervalSince1970)).jpg"
        let dest = CameraEngine.mediaDir.appendingPathComponent(name)
        try? longData.write(to: dest)
        _ = PHLibraryService.saveImage(longData)
        selectedIDs = []
        selecting = false
        store.load()
        detailItem = MediaItem(kind: .photo, filename: name, fileSize: Int64(longData.count))
    }

    // MARK: 系统相册

    private var systemGrid: some View {
        ScrollView {
            LazyVGrid(columns: galleryColumns, spacing: 3) {
                ForEach(systemItems) { sp in
                    SystemCell(photo: sp) {
                        detailSystem = sp
                    }
                }
            }
            .padding(.horizontal, 2)
            if systemItems.isEmpty {
                Text("系统相册为空或无权限")
                    .font(CNTheme.f12)
                    .foregroundStyle(Color(CNTheme.inkFaint))
                    .padding(.top, 40)
            }
        }
    }

    private func loadSystem() {
        Task { @MainActor in
            _ = await PHLibraryService.requestAuth()
            let items = PHLibraryService.systemMedia()
            systemItems = items
        }
    }
}

// MARK: - 单元格

struct MediaCell: View {
    let item: MediaItem
    let selected: Bool
    let isSelecting: Bool
    let onTap: () -> Void

    var body: some View {
        mediaThumb(item)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: CNTheme.r4))
            .overlay {
                if isSelecting {
                    Circle()
                        .fill(selected ? Color(CNTheme.cinnabar) : .white.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white, lineWidth: selected ? 0 : 1.5))
                        .offset(x: 12, y: -12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.kind == .video {
                    badge("video.fill")
                }
            }
            .onTapGesture(perform: onTap)
    }

    private func badge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(.black.opacity(0.45)))
    }

    @ViewBuilder
    private func mediaThumb(_ item: MediaItem) -> some View {
        let url = CameraEngine.mediaDir.appendingPathComponent(item.filename)
        if FileManager.default.fileExists(atPath: url.path),
           let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .frame(minWidth: 1, minHeight: 1)
        } else {
            Rectangle()
                .fill(Color(CNTheme.paperDeep))
                .overlay {
                    Image(systemName: item.kind == .photo ? "photo" : "video")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color(CNTheme.inkFaint))
                }
        }
    }
}

struct SystemCell: View {
    let photo: PHLibraryService.SystemPhoto
    let onTap: () -> Void
    @State private var thumb: UIImage?

    var body: some View {
        Group {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .frame(minWidth: 1, minHeight: 1)
            } else {
                Rectangle()
                    .fill(Color(CNTheme.paperDeep))
                    .overlay(ProgressView().tint(Color(CNTheme.inkFaint)))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: CNTheme.r4))
        .overlay(alignment: .bottomTrailing) {
            if photo.isVideo {
                Image(systemName: "video.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
        }
        .onTapGesture(perform: onTap)
        .onAppear { loadThumb() }
    }

    private func loadThumb() {
        guard thumb == nil else { return }
        Task { @MainActor in
            PHLibraryService.requestThumb(photo.assetID, size: CGSize(width: 300, height: 300)) { img in
                thumb = img
            }
        }
    }
}

// MARK: - 数据源

@MainActor
class MediaStore: ObservableObject {
    @Published var items: [MediaItem] = []

    func load() {
        let dir = CameraEngine.mediaDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            items = []
            return
        }
        var newItems: [MediaItem] = []
        for url in files {
            let ext = url.pathExtension.lowercased()
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            switch ext {
            case "jpg", "jpeg", "png", "pdf":
                newItems.append(MediaItem(kind: .photo, filename: url.lastPathComponent, date: date, fileSize: size))
            case "mov", "mp4":
                newItems.append(MediaItem(kind: .video, filename: url.lastPathComponent, date: date, fileSize: size))
            default:
                continue
            }
        }
        newItems.sort { $0.date > $1.date }
        items = newItems
    }

    func save(item: MediaItem) {
        items.insert(item, at: 0)
    }
}

// MARK: - 本机详情

struct MediaDetailView: View {
    let item: MediaItem
    @State private var showShare: Bool = false

    var body: some View {
        VStack(spacing: CNTheme.sp16) {
            HStack {
                Text(item.filename)
                    .font(CNTheme.f15)
                    .lineLimit(1)
                Spacer()
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(CNTheme.f15)
                        .foregroundStyle(Color(CNTheme.indigo))
                }
            }
            .padding(.horizontal, CNTheme.sp16)

            let mediaURL = CameraEngine.mediaDir.appendingPathComponent(item.filename)
            if FileManager.default.fileExists(atPath: mediaURL.path) {
                MediaDetailMedia(url: mediaURL)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, CNTheme.sp16)
            }

            VStack(spacing: CNTheme.sp8) {
                infoRow("类型", item.kind == .photo ? "照片 / 文档" : "视频")
                infoRow("日期", item.displayDate)
                infoRow("大小", item.displaySize)
                if let f = item.filterName {
                    infoRow("滤镜", f)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CNTheme.sp16)

            Spacer()
        }
        .presentationDetents([.medium])
        .background(CNTheme.pageBackground())
        .sheet(isPresented: $showShare) {
            if let data = try? Data(contentsOf: CameraEngine.mediaDir.appendingPathComponent(item.filename)) {
                ShareView(items: [data])
            } else {
                ShareView(items: [])
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(CNTheme.inkFaint))
            Spacer()
            Text(v).lineLimit(1)
        }
        .font(CNTheme.f14)
        .foregroundStyle(Color(CNTheme.ink))
    }
}

private struct MediaDetailMedia: View {
    let url: URL

    var body: some View {
        let ext = url.pathExtension.lowercased()
        Group {
            if ext == "mov" || ext == "mp4" {
                VideoDetailPlayer(url: url)
            } else {
                ImagePlaceholder(url: url)
            }
        }
        .frame(maxHeight: 340)
    }
}

private struct ImagePlaceholder: View {
    let url: URL
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("文档预览")
                    .font(CNTheme.f15)
                    .foregroundStyle(Color(CNTheme.inkSub))
            }
        }
        .onAppear {
            img = UIImage(contentsOfFile: url.path)
        }
    }
}

private struct VideoDetailPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: url)
            }
    }
}

// MARK: - 系统相册详情

struct SystemDetailSheet: View {
    let photo: PHLibraryService.SystemPhoto
    @State private var full: UIImage?
    @State private var player: AVPlayer?
    @State private var note: String = ""

    var body: some View {
        VStack(spacing: CNTheme.sp16) {
            if photo.isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxHeight: 300)
                } else {
                    videoPlaceholder
                }
            } else {
                if let full {
                    Image(uiImage: full)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: CNTheme.r8))
                } else {
                    imagePlaceholder
                }
            }

            if !note.isEmpty {
                Text(note)
                    .font(CNTheme.f12)
                    .foregroundStyle(Color(CNTheme.inkFaint))
            }

            HStack(spacing: CNTheme.sp16) {
                Button("存到本机") {
                    copyToLocal()
                }
                .buttonStyle(.bordered)
                .tint(Color(CNTheme.indigo))
                .disabled(full == nil && player == nil)
            }
        }
        .padding(CNTheme.sp16)
        .background(CNTheme.pageBackground())
        .presentationDetents([.large])
        .onAppear {
            fetch()
        }
    }

    private var imagePlaceholder: some View {
        VStack(spacing: CNTheme.sp8) {
            ProgressView()
            Text("加载中…")
                .font(CNTheme.f12)
                .foregroundStyle(Color(CNTheme.inkFaint))
        }
        .frame(maxHeight: 340)
    }

    private var videoPlaceholder: some View {
        VStack(spacing: CNTheme.sp8) {
            ProgressView()
            Text("视频导出中…")
                .font(CNTheme.f12)
                .foregroundStyle(Color(CNTheme.inkFaint))
        }
        .frame(maxHeight: 300)
    }

    private func fetch() {
        Task { @MainActor in
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.assetID], options: nil)
            guard let asset = result.firstObject else {
                note = "读取失败"
                return
            }
            PHLibraryService.requestFullImage(asset, targetSize: CGSize(width: 1600, height: 1600)) { img in
                full = img
            }
            if photo.isVideo {
                PHLibraryService.exportVideo(photo.assetID) { url in
                    if let url {
                        player = AVPlayer(url: url)
                    } else {
                        note = "视频导出失败"
                    }
                }
            }
        }
    }

    private func copyToLocal() {
        if photo.isVideo {
            PHLibraryService.exportVideo(photo.assetID) { url in
                guard let url else { return }
                let dest = CameraEngine.mediaDir
                    .appendingPathComponent("sys_\(Int(Date().timeIntervalSince1970)).m4v")
                try? FileManager.default.copyItem(at: url, to: dest)
                note = "已存到本机相册"
            }
        } else if let data = full?.jpegData(compressionQuality: 0.9) {
            let dest = CameraEngine.mediaDir
                .appendingPathComponent("sys_\(Int(Date().timeIntervalSince1970)).jpg")
            try? data.write(to: dest)
            note = "已存到本机相册"
        }
    }
}
