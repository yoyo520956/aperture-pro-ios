import AVFoundation
import Photos

/// Live Photo 保存服务
/// 相机 requestLivePhotoCapture 得到 .mov，按 Apple 官方范式
/// 把静态图（.photo）+ 配对视频（.pairedVideo）一起写进系统相册
/// 说明：AVCapturePhotoOutput 的 movieFileDataRepresentation() 已自带
/// Live Photo 配对 metadata（asset identifier / still image time），
/// 直接作为 .pairedVideo 资源即可，无需再 reader→writer 重封装。
@MainActor
enum LivePhotoService {
    static func saveLivePhoto(videoURL: URL, photoData: Data) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        } completionHandler: { success, error in
            NSLog("live photo saved: \(success) error: \(error?.localizedDescription ?? "-")")
        }
    }
}
