import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// 慢动作成片导出：120fps 源片 → 0.25× 合成 → 4 倍时长慢放成片（只取视频轨 = 去原声防变调）
/// 输出写到 Media 目录并直接进系统相册。
enum SlowMotionExporter {
    static func export(source: URL, speed: Float = 0.25) async -> Bool {
        let asset = AVURLAsset(url: source)
        guard let srcVideo = asset.tracks(withMediaType: .video).first else { return false }
        let rate = speed > 0 ? speed : 0.25

        let comp = AVMutableComposition()
        // 真实签名：addMutableTrack(withMediaType:preferredTrackID:)（只有两个参数，没有 from:/at:）
        guard let vTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        // 插入源视频区间：insertTimeRange(_:of:at:) 是 throws，不是 error: 指针
        let srcRange = srcVideo.timeRange
        do {
            try vTrack.insertTimeRange(srcRange, of: srcVideo, at: .zero)
        } catch {
            NSLog("[SlowMo] insertTimeRange 失败 \(error)")
            return false
        }
        // 变速：AVFoundation 没有 setSpeed(atStart:)，真实等价实现是
        // AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)（0.25× → 时长 1/0.25 = 4 倍）
        let timescale = max(1, srcRange.duration.timescale)
        let slowed = CMTime(seconds: srcRange.duration.seconds / Double(rate),
                            preferredTimescale: timescale)
        guard CMTIME_IS_VALID(slowed) && slowed.seconds > 0 else { return false }
        vTrack.scaleTimeRange(srcRange, toDuration: slowed)

        // 渲染尺寸（源 naturalSize × preferredTransform —— AVAssetTrack 没有 transform，只有 preferredTransform；偶数化）
        let applied = CGSizeApplyAffineTransform(srcVideo.naturalSize, srcVideo.preferredTransform)
        let size = CGSize(
            width: abs(applied.width).rounded(.down) / 2 * 2,
            height: abs(applied.height).rounded(.down) / 2 * 2
        )
        guard size.width >= 2, size.height >= 2 else { return false }

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        // 用源轨道 preferredTransform 摆正方向（原来的 identity 会把竖拍内容压成横躺）
        layer.setTransform(srcVideo.preferredTransform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: slowed)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        // 出帧时基跟随源帧率（120fps 源慢放 4× 后仍按源时基出帧，避免抽帧抖动）
        let fps = srcVideo.nominalFrameRate > 1 ? srcVideo.nominalFrameRate : 30
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        // AVMutableVideoComposition 没有 customCompositionTimeAssociation 这个属性；
        // 真实的帧时序开关是 sourceTrackIDForFrameTiming，kCMPersistentTrackID_Invalid = 跟随源帧
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        composition.instructions = [instruction]

        let outURL = CameraEngine.mediaDir.appendingPathComponent(
            "slowmo_\(Int(Date().timeIntervalSince1970)).mp4"
        )
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            return false
        }
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = composition

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // exportAsynchronously(completionHandler:) 的闭包不带参数，结果要读 session.status
            session.exportAsynchronously {
                let done = session.status == .completed
                if !done { NSLog("[SlowMo] 导出失败 status=\(session.status.rawValue) err=\(String(describing: session.error))") }
                DispatchQueue.main.async {
                    cont.resume(returning: done)
                }
            }
        }
        if ok {
            _ = PHLibraryService.saveVideo(outURL)
        }
        return ok
    }
}
