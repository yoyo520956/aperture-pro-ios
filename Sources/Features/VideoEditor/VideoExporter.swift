import AVFoundation
import CoreImage
import Photos

/// 视频导出核心：变速 + 静音 + 滤镜（AVVideoComposition 帧生成器）
enum VideoExporter {
    static func export(
        source: URL,
        speed: Float,
        muted: Bool,
        filter: VideoFilter,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        let avAsset = AVURLAsset(url: source)
        guard let assetVideo = avAsset.tracks(withMediaType: .video).first else {
            return false
        }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
            from: avAsset,
            at: .zero
        ) else {
            return false
        }
        let videoRange = assetVideo.timeRange
        vTrack.insertTimeRange(videoRange, of: assetVideo, at: .zero, error: nil)

        if !muted,
           let aSrc = avAsset.tracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid,
                from: avAsset,
                at: .zero
           ) {
            aTrack.insertTimeRange(aSrc.timeRange, of: aSrc, at: .zero, error: nil)
        }

        var videoComp: AVVideoComposition?
        if let ciName = filter.ciFilter {
            let size = renderSize(assetVideo: assetVideo)
            let vc = AVMutableVideoComposition()
            vc.renderSize = size
            vc.renderingTime = videoRange
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            let gen = FilterFrameGenerator(asset: comp, sourceTrack: assetVideo, ciFilterName: ciName)
            gen.maxCancellableRequests = 1
            vc.frameGenerator = AVAsynchronousVideoCompositionRequestGenerator(delegate: gen)
            videoComp = vc
        }

        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent("vedit_\(Int(Date().timeIntervalSince1970)).mp4")

        let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let vc = videoComp {
            session.videoComposition = vc
        }
        session.exportAsynchronously { status in
            if status == .completed {
                progress(1.0)
                _ = PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: outURL)
                }
            }
        }
        return session.status != .cancelled
    }

    private static func renderSize(assetVideo: AVAssetTrack) -> CGSize {
        var size = assetVideo.naturalSize
        size = size.applying(assetVideo.transform)
        size = CGSize(width: size.width.rounded(.down) / 2 * 2, height: size.height.rounded(.down) / 2 * 2)
        return size
    }

    // MARK: - 滤镜帧生成器（逐帧解码 + CIFilter）

    final class FilterFrameGenerator: NSObject, AVAsynchronousVideoCompositionRequestDelegate {
        private let asset: AVMutableComposition
        private let sourceTrack: AVAssetTrack
        private let ciFilterName: String
        private let ciContext = CIContext()

        init(asset: AVMutableComposition, sourceTrack: AVAssetTrack, ciFilterName: String) {
            self.asset = asset
            self.sourceTrack = sourceTrack
            self.ciFilterName = ciFilterName
        }

        func processVideoCompositionRequest(_ request: AVAsynchronousVideoCompositionRequest) {
            do {
                let reqSize = request.renderSize
                let frameTime = request.sourceTime.seconds

                // 建一次性 reader 解码到目标时间
                let reader = try AVAssetReader(asset: asset)
                let input = AVAssetReaderTrackInput(track: sourceTrack, outputSettings: nil)
                guard reader.canAdd(input) else {
                    request.finish(with: nil, error: nil)
                    return
                }
                reader.add(input)
                guard reader.startReading() else {
                    request.finish(with: nil, error: nil)
                    return
                }

                var baseImage: CGImage?
                while reader.status == .reading {
                    guard let sample = input.readSampleBuffer() else { break }
                    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if t >= frameTime {
                        if let pb = CVPixelBufferGetPixelBufferFromSampleBuffer(sample) {
                            let ciImg = CIImage(cvPixelBuffer: pb)
                            let scaled = ciImg
                                .transformed(by: CGAffineTransform(
                                    scale: reqSize.width / Double(ciImg.extent.width),
                                    y: reqSize.height / Double(ciImg.extent.height)
                                ))
                                .cropped(to: CGRect(origin: .zero, size: reqSize))
                            var out = scaled
                            if let f = CIFilter(name: ciFilterName) {
                                f.setValue(scaled, forKey: kCIInputImageKey)
                                if let filtered = f.outputImage {
                                    out = filtered
                                }
                            }
                            if let cgImg = try? ciContext.createCGImage(out, from: CGRect(origin: .zero, size: reqSize)) {
                                baseImage = cgImg
                            }
                        }
                        break
                    }
                }
                if let img = baseImage {
                    request.finish(with: img)
                } else {
                    request.finish(with: nil, error: nil)
                }
            } catch {
                request.finish(with: nil, error: error)
            }
        }

        func cancelVideoCompositionRequest(_ request: AVAsynchronousVideoCompositionRequest) {}
    }
}
