import Intents
import Photos
import UniformTypeIdentifiers
import Foundation

// MARK: - 分享扩展（无 UI · 直接把共享项入库系统相册）

/// 侧载 + 无 App Group 下最稳的入库方式：扩展直接写系统相册，
/// App 相册页本就读系统相册，无需跨进程手递
final class ApertureProShare: INExtension {
    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        guard let attachments = context.attachments, !attachments.isEmpty else {
            NSLog("[Share] 没有可入库的附件")
            return
        }
        var handled = 0
        for attachment in attachments {
            guard let type = attachment.registeredTypeIdentifier,
                  let ut = UTType(type) else { continue }
            if ut.conforms(to: .image) {
                attachment.loadContents(forTypeIdentifier: type) { [weak self] data, _ in
                    guard let data, !data.isEmpty else { return }
                    self?.saveImage(data)
                    handled += 1
                }
            } else if ut.conforms(to: .movie) {
                attachment.loadFile(atTypeIdentifier: type) { [weak self] url, _ in
                    guard let url else { return }
                    self?.saveMovie(url)
                    handled += 1
                }
            }
        }
        NSLog("[Share] 处理 \(attachments.count) 项共享内容 → 系统相册")
    }

    private func saveImage(_ data: Data) {
        PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: data)
        } completionHandler: { ok, _ in
            NSLog("[Share] 图片入库 \(ok)")
        }
    }

    private func saveMovie(_ url: URL) {
        PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { ok, _ in
            NSLog("[Share] 视频入库 \(ok) \(url.lastPathComponent)")
        }
    }
}
