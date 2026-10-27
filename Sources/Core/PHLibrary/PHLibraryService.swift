import AVFoundation
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
            // 官方范式：forAsset() + addResource(with:data:)
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        } completionHandler: { success, _ in
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
            // 官方范式：forAsset() + addResource(with:fileURL:)
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        } completionHandler: { success, _ in
            ok = success
            sem.signal()
        }
        sem.wait()
        return ok
    }

    static func saveLivePhoto(_ photoData: Data, videoURL: URL) -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 1)
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        } completionHandler: { success, _ in
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
    /// 官方 API：requestExportSession(forVideo:options:exportPreset:resultHandler:)
    /// 回调给的是 (AVAssetExportSession?, [AnyHashable: Any]?)
    static func exportVideo(_ assetID: String, completion: @escaping (URL?) -> Void) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else {
            completion(nil)
            return
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\(assetID).m4v")
        let options = PHVideoRequestOptions()
        PHImageManager.default().requestExportSession(
            forVideo: asset,
            options: options,
            exportPreset: AVAssetExportPresetHighestQuality
        ) { session, info in
            guard let session else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            session.outputURL = outURL
            session.outputFileType = .mp4
            try? FileManager.default.removeItem(at: outURL)
            session.exportAsynchronously {
                DispatchQueue.main.async {
                    if session.status == .completed, FileManager.default.fileExists(atPath: outURL.path) {
                        completion(outURL)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
}
