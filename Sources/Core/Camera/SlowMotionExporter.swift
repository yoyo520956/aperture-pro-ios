import AVFoundation
import CoreGraphics
import Foundation

/// 慢动作成片导出：120fps 源片 → 0.25× 合成 → 4 倍时长慢放成片（去原声防变调）
/// 输出写到 Media 目录并直接进系统相册。
enum SlowMotionExporter {
    static func export(source: URL, speed: Float = 0.25) async -> Bool {
        let asset = AVURLAsset(url: source)
        guard let srcVideo = asset.tracks(withMediaType: .video).first else { return false }

        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
            from: asset,
            at: .zero
        ) else { return false }
        vTrack.insertTimeRange(srcVideo.timeRange, of: srcVideo, at: .zero, error: nil)
        vTrack.setSpeed(speed, atStart: .zero)

        // 渲染尺寸（源 naturalSize × transform，偶数化）
        var size = srcVideo.naturalSize
        size = size.applying(srcVideo.transform)
        size = CGSize(
            width: size.width.rounded(.down) / 2 * 2,
            height: size.height.rounded(.down) / 2 * 2
        )
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        layer.setTransform(CGAffineTransform.identity, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = vTrack.timeRange
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.customCompositionTimeAssociation = .relativeToEachTrack
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
            session.exportAsynchronously { status in
                DispatchQueue.main.async {
                    cont.resume(returning: status == .completed)
                }
            }
        }
        if ok {
            _ = PHLibraryService.saveVideo(outURL)
        }
        return ok
    }
}
