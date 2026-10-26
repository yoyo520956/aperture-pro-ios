import SwiftUI

struct GalleryView: View {
    @StateObject private var store = MediaStore()
    @State private var selectedMedia: MediaItem?
    @State private var showDetail: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                let columns = [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(store.items) { item in
                        GalleryThumbnail(item: item)
                            .onTapGesture {
                                selectedMedia = item
                                showDetail = true
                            }
                    }
                }
                if store.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("暂无媒体文件")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("拍一张照片开始吧")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .navigationTitle("相册")
            .navigationSubtitle("\(store.items.count) 项")
        }
        .sheet(isPresented: $showDetail) {
            if let item = selectedMedia {
                MediaDetailView(item: item)
            }
        }
        .onAppear { store.load() }
    }
}

struct GalleryThumbnail: View {
    let item: MediaItem

    var body: some View {
        Rectangle()
            .fill(.gray)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: item.kind == .photo ? "camera.fill" : "video.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .padding(4)
                }
            }
    }
}

struct MediaDetailView: View {
    let item: MediaItem
    @State private var showShare: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: item.kind == .photo ? "camera.fill" : "video.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray)
                Spacer()
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal)

            Grid {
                GridRow {
                    Text("文件名").foregroundStyle(.secondary)
                    Text(item.filename).lineLimit(1)
                }
                GridRow {
                    Text("类型").foregroundStyle(.secondary)
                    Text(item.kind == .photo ? "照片" : item.kind == .video ? "视频" : "频闪")
                }
                GridRow {
                    Text("日期").foregroundStyle(.secondary)
                    Text(item.displayDate)
                }
                GridRow {
                    Text("大小").foregroundStyle(.secondary)
                    Text(item.displaySize)
                }
                if let filter = item.filterName {
                    GridRow {
                        Text("滤镜").foregroundStyle(.secondary)
                        Text(filter)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .sheet(isPresented: $showShare) {
            ShareView(items: [])
        }
    }
}

struct MediaStore: ObservableObject {
    @Published var items: [MediaItem] = []

    func load() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mediaDir = docs.appendingPathComponent("Media", isDirectory: true)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
            items = files.compactMap { url in
                let ext = url.pathExtension
                if ext == "jpg" || ext == "jpeg" || ext == "png" {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    return MediaItem(kind: .photo, filename: url.lastPathComponent, fileSize: size ?? 0)
                } else if ext == "mov" || ext == "mp4" {
                    return MediaItem(kind: .video, filename: url.lastPathComponent)
                }
                return nil
            }
            items.sort { $0.date > $1.date }
        } catch {
            items = []
        }
    }

    func save(item: MediaItem) {
        items.insert(item, at: 0)
    }
}
