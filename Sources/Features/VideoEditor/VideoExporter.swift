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

// MARK: - 多段时间轴 + 交叉淡化转场

    struct MultiSegment {
        var url: URL
        var start: Double      // 源内起点（秒）
        var duration: Double   // 源内取片长（秒）
        var speed: Float
        var filter: VideoFilter
        var mutedSegment: Bool = false
        var fade: Bool         // 本段尾部与下一段交叉淡化（0.5s）
    }

    /// 多段合成导出：
    /// - 各段可带 入点/时长/倍速/滤镜，段尾可选 0.5s 交叉淡化（视频层 opacity 动画 + 音频音量斜坡）
    /// - 滤镜段先离线渲染中间文件（复用 renderFiltered），再组 AVMutableComposition
    static func exportMulti(
        _ segments: [MultiSegment],
        muted: Bool,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        guard segments.count >= 1 else { return false }
        let n = segments.count
        let fadeLen: Double = 0.5

        // 1) 滤镜段预渲染
        var staged: [URL] = []
        var finals: [URL] = []
        var temps: [URL] = []
        for seg in segments {
            if let name = seg.filter.ciFilter {
                guard let st = renderFiltered(seg.url, ciFilterName: name) else { return false }
                temps.append(st)
                finals.append(st)
            } else {
                finals.append(seg.url)
            }
        }
        defer { for u in temps { try? FileManager.default.removeItem(at: u) } }

        // 2) 各段 asset + 时长
        var assets: [AVAsset] = []
        for u in finals { assets.append(AVURLAsset(url: u)) }
        guard assets.allSatisfy({ $0.loadValue(forKey: "duration").take() != nil }) else { return false }
        var outDurs: [Double] = []
        for i in 0..<n {
            let dur = min(segments[i].duration, assetDuration(assets[i]) - segments[i].start)
            outDurs.append(max(0.5, dur / Double(segments[i].speed)))
        }

        // 3) 时间线位置（段尾 fade 时下一段前移 overlap）
        var pos: [Double] = [0]
        for i in 1..<n {
            let prevEnd = pos[i - 1] + outDurs[i - 1]
            pos.append(segments[i - 1].fade ? max(prevEnd - fadeLen, pos[i - 1]) : prevEnd)
        }
        let totalEnd = pos[n - 1] + outDurs[n - 1]
        guard totalEnd > 0.5 else { return false }

        // 4) AVMutableComposition（每段独立轨道，按时间轴位置插入）
        let comp = AVMutableComposition()
        var vTracks: [AVMutableCompositionTrack] = []
        var aMix = AVMutableAudioMix()
        for i in 0..<n {
            let asset = assets[i]
            let srcRange = CMTimeRange(
                start: CMTime(seconds: segments[i].start, preferredTimescale: 1000),
                duration: CMTime(seconds: outDurs[i] * Double(segments[i].speed), preferredTimescale: 1000)
            )
            guard let vt = comp.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid,
                from: asset,
                at: CMTime(seconds: pos[i], preferredTimescale: 1000)
            ) else { return false }
            guard let srcV = asset.tracks(withMediaType: .video).first else { return false }
            vt.insertTimeRange(srcRange, of: srcV, at: CMTime(seconds: pos[i], preferredTimescale: 1000), error: nil)
            vt.setSpeed(segments[i].speed, atStart: CMTime(seconds: pos[i], preferredTimescale: 1000))
            vTracks.append(vt)
            if !muted, let srcA = asset.tracks(withMediaType: .audio).first {
                if let at = comp.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid,
                    from: asset,
                    at: CMTime(seconds: pos[i], preferredTimescale: 1000)
                ) {
                    at.insertTimeRange(srcRange, of: srcA, at: CMTime(seconds: pos[i], preferredTimescale: 1000), error: nil)
                    at.setSpeed(segments[i].speed, atStart: CMTime(seconds: pos[i], preferredTimescale: 1000))
                    if let params = AVMutableAudioMixInputParameters(track: at) {
                        params.setVolume(segments[i].mutedSegment ? 0 : 1, at: CMTime(seconds: pos[i], preferredTimescale: 1000))
                        aMix.audioMixInputs.append(params)
                    }
                }
            }
        }
        comp.audioMix = aMix

        // 5) 视频合成指令：solo 区 + 重叠区（双层 opacity 动画）
        var size = assets.first?.tracks(withMediaType: .video).first?.naturalSize ?? CGSize(width: 1080, height: 1920)
        size = CGSize(width: size.width.rounded(.down) / 2 * 2, height: size.height.rounded(.down) / 2 * 2)

        func layerFor(_ i: Int, startT: Double, endT: Double, fadeHead: Bool, fadeTail: Bool) -> AVMutableVideoCompositionLayerInstruction {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTracks[i])
            layer.setTransform(CGAffineTransform.identity, at: CMTime(seconds: startT, preferredTimescale: 1000))
            if fadeHead {
                layer.setOpacity(0.0, at: CMTime(seconds: startT, preferredTimescale: 1000))
                layer.setOpacity(1.0, at: CMTime(seconds: startT + fadeLen, preferredTimescale: 1000))
            } else {
                layer.setOpacity(1.0, at: CMTime(seconds: startT, preferredTimescale: 1000))
            }
            if fadeTail {
                layer.setOpacity(1.0, at: CMTime(seconds: endT - fadeLen, preferredTimescale: 1000))
                layer.setOpacity(0.0, at: CMTime(seconds: endT, preferredTimescale: 1000))
            }
            return layer
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for i in 0..<n {
            let segStart = pos[i]
            let segEnd = pos[i] + outDurs[i]
            let headFade = (i > 0 && segments[i - 1].fade) ? true : false
            let tailFade = (i + 1 < n && segments[i].fade) ? true : false
            let soloStart = segStart + (headFade ? fadeLen : 0)
            let soloEnd = segEnd - (tailFade ? fadeLen : 0)
            // solo 区
            if soloEnd > soloStart {
                let ins = AVMutableVideoCompositionInstruction()
                ins.timeRange = CMTimeRange(
                    start: CMTime(seconds: soloStart, preferredTimescale: 1000),
                    end: CMTime(seconds: soloEnd, preferredTimescale: 1000))
                ins.layerInstructions = [layerFor(i, startT: soloStart, endT: soloEnd, fadeHead: false, fadeTail: false)]
                instructions.append(ins)
            }
            // 与上一段的重叠区（双层交叉淡化）
            if headFade {
                let ins = AVMutableVideoCompositionInstruction()
                ins.timeRange = CMTimeRange(
                    start: CMTime(seconds: segStart, preferredTimescale: 1000),
                    end: CMTime(seconds: segStart + fadeLen, preferredTimescale: 1000))
                ins.layerInstructions = [
                    layerFor(i - 1, startT: segStart, endT: segStart + fadeLen, fadeHead: false, fadeTail: true),
                    layerFor(i, startT: segStart, endT: segStart + fadeLen, fadeHead: true, fadeTail: false)
                ]
                instructions.append(ins)
            }
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.customCompositionTimeAssociation = .relativeToEachTrack
        composition.instructions = instructions

        // 6) 导出
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent("vedit_multi_\(Int(Date().timeIntervalSince1970)).mp4")
        let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = composition
        session.progressHandler = { p in
            DispatchQueue.main.async { progress(Double(p) * 0.95) }
        }
        let completed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            session.exportAsynchronously { status in
                DispatchQueue.main.async {
                    progress(1.0)
                    cont.resume(returning: status == .completed)
                }
            }
        }
        guard completed else { return false }
        _ = PHLibraryService.saveVideo(outURL)
        return true
    }

    private static func assetDuration(_ asset: AVAsset) -> Double {
        Double(asset.duration.seconds)
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
