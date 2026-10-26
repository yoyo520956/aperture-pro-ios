import Intents
import Foundation
import Photos
import UniformTypeIdentifiers

#if canImport(ExtensionFoundation)
import ExtensionFoundation
#endif

// MARK: - 分享扩展主类（无 UI · 直接把共享项入库系统相册）

/// 侧载 + 无 App Group 下最稳的入库方式：扩展直接写系统相册。
/// App 相册页本就读系统相册，无需跨进程手递。
final class ApertureProShare: NSExtension {
    override init(extensionParameters: NSExtensionParameters) {
        super.init(extensionParameters: extensionParameters)
        if let ctx = extensionParameters.context {
            ingest(context: ctx)
        } else {
            NSLog("[Share] 无扩展上下文")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    private func ingest(context: NSExtensionContext) {
        guard let items = context.attachments, !items.isEmpty else {
            NSLog("[Share] 没有可入库的附件")
            return
        }
        var total = 0
        for item in items {
            total += save(item: item)
        }
        NSLog("[Share] 入库 \(total) 项 → 系统相册")
    }

    /// 处理一个 NSExtensionItem，返回实际入库数
    private func save(item: NSExtensionItem) -> Int {
        var count = 0
        for provider in item.attachments {
            guard let type = provider.registeredTypeIdentifier,
                  let ut = UTType(type) else { continue }
            if ut.conforms(to: .image) {
                provider.loadContents(forTypeIdentifier: type) { data, _ in
                    guard let data, !data.isEmpty else { return }
                    self.saveImage(data)
                }
                count += 1
            } else if ut.conforms(to: .movie) {
                provider.loadFile(atTypeIdentifier: type) { url, _ in
                    guard let url else { return }
                    self.saveMovie(url)
                }
                count += 1
            }
        }
        return count
    }

    private func saveImage(_ data: Data) {
        let req = PHAssetCreationRequest.forAsset()
        req.addPhoto(with: data, options: nil)
        PHPhotoLibrary.shared().performChanges {
        } completionHandler: { ok, _ in
            NSLog("[Share] 图片入库 \(ok)")
        }
    }

    private func saveMovie(_ url: URL) {
        PHPhotoLibrary.shared().performChanges {
            _ = PHAssetCreationRequest.forAssetFromVideo(atFileURL: url)
        } completionHandler: { ok, _ in
            NSLog("[Share] 视频入库 \(ok) \(url.lastPathComponent)")
        }
    }
}
