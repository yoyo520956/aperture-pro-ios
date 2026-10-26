import AVFoundation
import CoreImage
import Photos

/// 视频导出核心：变速 + 静音 + 滤镜
/// 滤镜走离线两遍：先逐帧过 CIFilter 顺序写成中间文件（不做随机 seek），
/// 再用 AVAssetExportSession 组 composition 应用速度与静音
enum VideoExporter {
    static func export(
        source: URL,
        speed: Float,
        muted: Bool,
        filter: VideoFilter,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        var temps: [URL] = []
        let stagedURL: URL
        if let name = filter.ciFilter {
            guard let staged = renderFiltered(source, ciFilterName: name) else {
                return false
            }
            temps.append(staged)
            stagedURL = staged
        } else {
            stagedURL = source
        }
        defer {
            for u in temps {
                try? FileManager.default.removeItem(at: u)
            }
        }

        // 组 composition
        let asset = AVURLAsset(url: stagedURL)
        guard let srcVideo = asset.tracks(withMediaType: .video).first else {
            return false
        }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
            from: asset,
            at: .zero
        ) else {
            return false
        }
        vTrack.insertTimeRange(srcVideo.timeRange, of: srcVideo, at: .zero, error: nil)
        vTrack.setSpeed(speed, atStart: .zero)

        if !muted,
           let srcAudio = asset.tracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid,
                from: asset,
                at: .zero
           ) {
            aTrack.insertTimeRange(srcAudio.timeRange, of: srcAudio, at: .zero, error: nil)
            aTrack.setSpeed(speed, atStart: .zero)
        }

        // 变速后合成时间 ≠ 源时间，必须显式声明映射关系
        let size = renderSize(assetVideo: srcVideo)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        layer.setTransform(CGAffineTransform.identity, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = vTrack.timeRange
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.customCompositionTimeAssociation = .relativeToEachTrack
        composition.instructions = [instruction]

        // 导出
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent("vedit_\(Int(Date().timeIntervalSince1970)).mp4")

        let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = composition
        session.progressHandler = { p in
            let v = Double(p)
            DispatchQueue.main.async { progress(v) }
        }

        progress(0.05)
        let completed = await withCheckedContinuation { continuation in
            session.exportAsynchronously { status in
                DispatchQueue.main.async { progress(1.0) }
                continuation.resume(returning: status == .completed)
            }
        }

        guard completed else { return false }
        _ = PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: outURL)
        }
        return true
    }

    private static func renderSize(assetVideo: AVAssetTrack) -> CGSize {
        var size = assetVideo.naturalSize
        size = size.applying(assetVideo.transform)
        return CGSize(
            width: size.width.rounded(.down) / 2 * 2,
            height: size.height.rounded(.down) / 2 * 2
        )
    }

    // MARK: - 滤镜离线渲染（顺序读写，不做随机 seek）

    private static func renderFiltered(_ source: URL, ciFilterName: String) -> URL? {
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        var size = track.naturalSize
        size = size.applying(track.transform)
        let w = Int(size.width.rounded(.down) / 2 * 2)
        let h = Int(size.height.rounded(.down) / 2 * 2)
        guard w > 0, h > 0 else { return nil }

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let trackInput = AVAssetReaderTrackInput(track: track, outputSettings: nil)
        guard reader.canAdd(trackInput) else { return nil }
        reader.add(trackInput)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vedit_filter_\(Int(Date().timeIntervalSince1970)).mp4")
        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mp4) else { return nil }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealtime = false
        guard writer.canInput(writerInput) else { return nil }
        writer.add(writerInput)

        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h
        ]
        guard let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: poolAttrs
        ) else { return nil }

        let finished = DispatchSemaphore(value: 0)
        writer.addFinishedWritingCallback { _ in finished.signal() }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        let ciContext = CIContext()
        let filter = CIFilter(name: ciFilterName)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        while reader.status == .reading {
            waitReady(writerInput)
            guard let sample = trackInput.readSampleBuffer() else { break }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)

            var image: CGImage?
            if let pb = CVPixelBufferGetPixelBufferFromSampleBuffer(sample) {
                var ci = CIImage(cvPixelBuffer: pb)
                if let filter {
                    filter.setValue(ci, forKey: kCIInputImageKey)
                    if let out = filter.outputImage { ci = out }
                }
                ci = ci.scaled(toFit: rect).cropped(to: rect)
                image = ciContext.createCGImage(ci, from: rect)
            }

            if let cg = image,
               let pixel = makePixelBuffer(adaptor: adaptor),
               let base = CVPixelBufferGetBaseAddress(pixel) {
                CVPixelBufferLockBaseAddress(pixel, [])
                if let ctx = CGContext(
                    data: base, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: Int(CVPixelBufferGetBytesPerRow(pixel)),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                ) {
                    ctx.draw(cg, in: rect)
                }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                adaptor.append(pixel, withPresentationTime: pts)
            } else {
                writerInput.append(sample, withPresentationTime: pts)
            }
        }

        adaptor.markAsFinished()
        writer.finishWriting()
        _ = finished.wait(timeout: .now() + 120)

        guard writer.status == .completed,
              FileManager.default.fileExists(atPath: outURL.path) else {
            NSLog("vedit 滤镜渲染失败: \(writer.error?.localizedDescription ?? "未知")")
            return nil
        }
        return outURL
    }

    private static func makePixelBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private static func waitReady(_ input: AVAssetWriterInput, tries: Int = 500) {
        var i = 0
        while !input.isReadyForMoreMediaData, i < tries {
            i += 1
            usleep(20_000)
        }
    }
}
