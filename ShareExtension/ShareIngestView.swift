import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers

#if canImport(ExtensionFoundation)
import ExtensionFoundation
#endif

// MARK: - UI 状态

final class ShareIngestModel: ObservableObject {
    @Published var status: String = "等待共享内容…"
    @Published var failed: Bool = false
    @Published var done: Bool = false
    var savedCount: Int = 0
    var failedCount: Int = 0
}

// MARK: - 分享卡片

struct ShareIngestCard: View {
    @ObservedObject var model: ShareIngestModel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((model.failed ? Color.orange : Color.blue).opacity(0.12))
                    .frame(width: 78, height: 78)
                Image(systemName: model.failed ? "exclamationmark.triangle.fill" : "camera.aperture")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(model.failed ? Color.orange : Color.blue)
            }
            Text("光圈 Pro")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.done && !model.failed {
                Text("已写入 \(model.savedCount) 项到系统相册")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - 分享扩展主类

/// 真正的分享入口：从 extensionContext 取用户分享的图像/视频，写入系统相册。
/// 关键：共享内容通过 NSItemProvider 传递，**不需要 App Group**，
/// 因此侧载（无 App Group 授权）也能正常工作。
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let model = ShareIngestModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let card = UIHostingController(rootView: ShareIngestCard(model: model))
        addChild(card)
        card.view.frame = view.bounds
        card.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(card.view)
        card.didMove(toParent: self)
        Task { await ingest() }
    }

    // MARK: 读取共享内容

    private func ingest() async {
        model.status = "正在读取共享内容…"
        guard let ctx = extensionContext else {
            fail("扩展上下文不可用")
            return
        }
        let items = ctx.inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            fail("没有可处理的共享内容")
            return
        }

        var images: [Data] = []
        var movies: [URL] = []
        for provider in providers {
            if let type = pickType(provider, conforms: .image),
               let data = await loadData(provider, type) {
                images.append(data)
            } else if let type = pickType(provider, conforms: .movie),
                      let url = await loadFile(provider, type) {
                movies.append(url)
            }
        }
        guard !images.isEmpty || !movies.isEmpty else {
            fail("无法识别的内容格式")
            return
        }

        model.status = "正在写入系统相册…"
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else {
            fail("未获得相册写入权限")
            return
        }

        let ok = await writeToLibrary(images: images, movies: movies)
        if ok {
            model.savedCount = images.count + movies.count
            model.failedCount = 0
            model.done = true
            model.failed = false
            model.status = "写入完成"
            NSLog("[Share] 写入成功 \(images.count) 图 \(movies.count) 视频")
        } else {
            fail("写入相册失败")
        }
        ctx.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func fail(_ message: String) {
        model.failed = true
        model.done = true
        model.status = message
        NSLog("[Share] 失败: \(message)")
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: NSItemProvider 读取

    /// 在 provider 注册的类型里找一个符合目标类型的（优先精确匹配）
    private func pickType(_ provider: NSItemProvider, conforms target: UTType) -> String? {
        let registered = provider.registeredTypeIdentifiers
        if registered.contains(target.identifier) { return target.identifier }
        for id in registered {
            guard let t = UTType(id) else { continue }
            if t.conforms(to: target) { return id }
        }
        return nil
    }

    /// 读图片数据（优先 fileRepresentation，避免超大图走 dataRepresentation）
    private func loadData(_ provider: NSItemProvider, _ typeId: String) async -> Data? {
        if let url = await loadFile(provider, typeId) {
            return try? Data(contentsOf: url)
        }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// 读文件（NSItemProvider 给的临时 URL 需立即拷贝，返回副本）
    private func loadFile(_ provider: NSItemProvider, _ typeId: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share_\(UUID().uuidString).\(url.pathExtension)")
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: 写入系统相册

    /// 官方正确姿势：PHAssetCreationRequest.forAsset() + addResource(with:data:options:)
    /// （不存在 creationRequestForAsset(from: Data) 这个 API）
    private func writeToLibrary(images: [Data], movies: [URL]) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for data in images {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
                for url in movies {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: url, options: nil)
                }
            } completionHandler: { success, error in
                if let error {
                    NSLog("[Share] performChanges error: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
