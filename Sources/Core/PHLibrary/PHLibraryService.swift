import Photos
import UIKit
import Foundation

/// 系统相册读写服务（PHPhotoLibrary）
/// 保存照片 / 视频进系统相册，拉取系统照片缩略图进画廊
enum PHLibraryService {
    static func requestAuth() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    static func saveImage(_ data: Data) -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 1)
        PHPhotoLibrary.shared().performChanges {
            guard let asset = PHAssetChangeRequest.creationRequestForAsset(from: data) as? PHAsset else {
                return
            }
            _ = asset
        } completionHandler: { success in
            ok = success
            sem.signal()
        }
        sem.wait()
        return ok
    }

    static func saveVideo(_ url: URL) -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 1)
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: url)
        } completionHandler: { success in
            ok = success
            sem.signal()
        }
        sem.wait()
        return ok
    }

    struct SystemPhoto: Identifiable {
        let id: String
        let thumb: UIImage?
        let isVideo: Bool
        let assetID: String
    }

    /// 最近 limit 条系统媒体（占位，缩略图由视图各自加载）
    static func systemMedia(limit: Int = 120) -> [SystemPhoto] {
        let options = PHFetchOptions()
        options.resultType = .image
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options, options: nil)
        var out: [SystemPhoto] = []
        var index = 0
        while index < result.count && out.count < limit {
            let asset = result.object(at: index)
            out.append(SystemPhoto(
                id: asset.localIdentifier,
                thumb: nil,
                isVideo: asset.mediaType == .video,
                assetID: asset.localIdentifier
            ))
            index += 1
        }
        return out
    }

    /// 按本地标识取缩略图
    static func requestThumb(_ assetID: String, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else {
            completion(nil)
            return
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// 大图（详情预览用）
    static func requestFullImage(_ asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// 视频导出到临时目录
    static func exportVideo(_ assetID: String, completion: @escaping (URL?) -> Void) {
        let options = PHFetchOptions()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard result.count > 0, let asset = result.firstObject else {
            completion(nil)
            return
        }
        let options2 = PHVideoExportSession(options: PHVideoExportPreset.muxFormatH264AVCProfileBaseline)
        options2.outputFileType = .mpeg4
        let session = PHVideoExportSession(asset: asset, options: options2)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\(assetID).m4v")
        session.outputFileURL = outURL
        session.startExporting { status, _ in
            DispatchQueue.main.async {
                if status == .completed, FileManager.default.fileExists(atPath: outURL.path) {
                    completion(outURL)
                } else {
                    completion(nil)
                }
            }
        }
    }
}
