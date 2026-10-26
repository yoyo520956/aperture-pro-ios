import AVFoundation
import Photos

/// Live Photo 保存服务
/// 相机 requestLivePhotoCapture 得到 .mov 后，按 Apple 官方范式
/// 组装 AVLivePhotoPhoto，和照片一起写进系统相册
@MainActor
enum LivePhotoService {
    static func saveLivePhoto(videoURL: URL, photoData: Data) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addPhoto(from: photoData, options: nil)
            if let lp = buildLivePhoto(videoURL: videoURL) {
                request.addLivePhoto(lp)
            }
        } completionHandler: { success, _ in
            NSLog("live photo saved: \(success)")
        }
    }

    /// 官方 WWDC17 范式：reader→writer 复制 mov，再包 AVLivePhotoPhoto
    private nonisolated static func buildLivePhoto(videoURL: URL) -> AVLivePhotoPhoto? {
        let srcAsset = AVURLAsset(url: videoURL)
        guard let track = srcAsset.tracks(with: .video).first else { return nil }
        do {
            let reader = try AVAssetReader(asset: srcAsset)
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(readerOutput)

            let writerURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("liveout_\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: writerURL, fileType: .mov)
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            guard writer.canInput(writerInput) else { return nil }
            writer.add(writerInput)

            reader.startReading()
            writer.startWriting()
            writer.startSession()
            while reader.status == .reading,
                  let sample = readerOutput.copyNextSampleBuffer() {
                if writerInput.isReadyForMoreMediaData {
                    writerInput.append(sample)
                }
            }
            writerInput.markAsFinished()
            writer.finishWriting { _ in }
            return AVLivePhotoPhoto(asset: AVURLAsset(url: writerURL), previewImageKey: .default)
        } catch {
            NSLog("live photo build error: \(error.localizedDescription)")
            return nil
        }
    }
}
