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

        // 组 composition（官方：addMutableTrack + insertTimeRange + scaleTimeRange 变速）
        let asset = AVURLAsset(url: stagedURL)
        guard let srcVideo = asset.tracks(withMediaType: .video).first else {
            return false
        }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return false
        }
        do {
            try vTrack.insertTimeRange(srcVideo.timeRange, of: srcVideo, at: .zero)
        } catch {
            NSLog("vedit insert video failed: %@", error.localizedDescription)
            return false
        }
        if abs(Double(speed) - 1.0) > 0.001 {
            let srcDur = srcVideo.timeRange.duration.seconds
            vTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: srcDur, preferredTimescale: 1000)),
                toDuration: CMTime(seconds: srcDur / Double(speed), preferredTimescale: 1000)
            )
        }

        if !muted,
           let srcAudio = asset.tracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            do {
                try aTrack.insertTimeRange(srcAudio.timeRange, of: srcAudio, at: .zero)
                if abs(Double(speed) - 1.0) > 0.001 {
                    let aDur = srcAudio.timeRange.duration.seconds
                    aTrack.scaleTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: aDur, preferredTimescale: 1000)),
                        toDuration: CMTime(seconds: aDur / Double(speed), preferredTimescale: 1000)
                    )
                }
            } catch {
                NSLog("vedit insert audio failed: %@", error.localizedDescription)
            }
        }

        let size = renderSize(assetVideo: srcVideo)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        layer.setTransform(CGAffineTransform.identity, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: comp.duration.seconds, preferredTimescale: 1000))
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.instructions = [instruction]

        // 导出
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent("vedit_\(Int(Date().timeIntervalSince1970)).mp4")

        guard let session = AVAssetExportSession(
            asset: comp, presetName: AVAssetExportPresetHighestQuality
        ) else { return false }
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = composition

        progress(0.05)
        let completed: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pollProgress(session: session, untilDone: { cont.resume(returning: session.status == .completed) },
                         scale: 0.95, progress: progress)
            session.exportAsynchronously {}
        }

        guard completed else { return false }
        DispatchQueue.main.async { progress(1.0) }
        PHLibraryService.saveVideo(outURL)
        return true
    }

    /// 导出进度轮询（AVAssetExportSession.progress 只读，0.5s 一次，导出结束自动停）
    private static func pollProgress(
        session: AVAssetExportSession,
        untilDone: @escaping () -> Void,
        scale: Double,
        progress: @escaping (Double) -> Void
    ) {
        let q = DispatchQueue(label: "vedit.progress")
        q.asyncAfter(deadline: .now() + 0.5) {
            switch session.status {
            case .completed, .failed, .cancelled:
                untilDone()
            default:
                let p = Double(session.progress) * scale
                DispatchQueue.main.async { progress(p) }
                pollProgress(session: session, untilDone: untilDone, scale: scale, progress: progress)
            }
        }
    }

    private static func renderSize(assetVideo: AVAssetTrack) -> CGSize {
        var size = assetVideo.naturalSize
        size = size.applying(assetVideo.preferredTransform)
        return CGSize(
            width: abs(size.width).rounded(.down) / 2 * 2,
            height: abs(size.height).rounded(.down) / 2 * 2
        )
    }

    // MARK: - 滤镜离线渲染（顺序读写，不做随机 seek）

    private static func renderFiltered(_ source: URL, ciFilterName: String) -> URL? {
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        var size = track.naturalSize
        size = size.applying(track.preferredTransform)
        let w = Int(abs(size.width).rounded(.down) / 2 * 2)
        let h = Int(abs(size.height).rounded(.down) / 2 * 2)
        guard w > 0, h > 0 else { return nil }

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        // 官方解码输出（不设 outputSettings = 压缩样本直通，滤镜分支会自己解码）
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(trackOutput) else { return nil }
        reader.add(trackOutput)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vedit_filter_\(Int(Date().timeIntervalSince1970)).mp4")
        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mp4) else { return nil }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        guard writer.canAdd(writerInput) else { return nil }
        writer.add(writerInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ]
        )

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        let ciContext = CIContext()
        let filter = CIFilter(name: ciFilterName)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        while reader.status == .reading {
            waitReady(writerInput)
            guard let sample = trackOutput.copyNextSampleBuffer() else { break }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)

            var cg: CGImage?
            if let pb = CMSampleBufferGetImageBuffer(sample) {
                var ci = CIImage(cvPixelBuffer: pb)
                if let filter {
                    filter.setValue(ci, forKey: kCIInputImageKey)
                    if let out = filter.outputImage { ci = out }
                }
                // 等比缩放到目标尺寸再裁
                let ext = ci.extent
                if ext.width > 0, ext.height > 0 {
                    let s = min(rect.width / ext.width, rect.height / ext.height)
                    ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
                }
                cg = ciContext.createCGImage(ci.cropped(to: rect), from: rect)
            }

            if let cg,
               let pixel = makePixelBuffer(adaptor: adaptor) {
                CVPixelBufferLockBaseAddress(pixel, [])
                defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
                if let base = CVPixelBufferGetBaseAddress(pixel),
                   let ctx = CGContext(
                    data: base, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                   ) {
                    ctx.draw(cg, in: rect)
                }
                adaptor.append(pixel, withPresentationTime: pts)
            } else {
                // 滤镜失败时原帧直通（保行为不中断）
                waitReady(writerInput)
                writerInput.append(sample)
            }
        }

        writerInput.markAsFinished()
        writer.finishWriting()

        guard writer.status == .completed,
              FileManager.default.fileExists(atPath: outURL.path) else {
            NSLog("vedit 滤镜渲染失败: %@", writer.error?.localizedDescription ?? "未知")
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
    /// - 各段可带 入点/时长/倍速/滤镜，段尾可选 0.5s 交叉淡化（视频层 opacity 斜坡 + 音频逐段静音）
    /// - 滤镜段先离线渲染中间文件（复用 renderFiltered），再组 AVMutableComposition
    static func exportMulti(
        _ segments: [MultiSegment],
        muted: Bool,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        guard segments.count >= 1 else { return false }
        let n = segments.count
        let fadeLen: Double = 0.5
        let ts: Int32 = 1000

        func ct(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: ts) }

        // 1) 滤镜段预渲染
        var temps: [URL] = []
        var finals: [URL] = []
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
        let assets: [AVAsset] = finals.map { AVURLAsset(url: $0) }
        guard assets.allSatisfy({ $0.duration.seconds > 0.1 }) else { return false }
        var outDurs: [Double] = []
        for i in 0..<n {
            let avail = max(0.1, assetDuration(assets[i]) - segments[i].start)
            let dur = min(segments[i].duration, avail)
            outDurs.append(max(0.5, dur / Double(max(segments[i].speed, 0.1))))
        }

        // 3) 时间线位置（段尾 fade 时下一段前移 overlap）
        var pos: [Double] = [0]
        for i in 1..<n {
            let prevEnd = pos[i - 1] + outDurs[i - 1]
            pos.append(segments[i - 1].fade ? max(prevEnd - fadeLen, pos[i - 1]) : prevEnd)
        }
        let totalEnd = pos[n - 1] + outDurs[n - 1]
        guard totalEnd > 0.5 else { return false }

        // 4) AVMutableComposition：每段独立轨道，insertTimeRange + scaleTimeRange变速
        let comp = AVMutableComposition()
        var vTracks: [AVMutableCompositionTrack] = []
        var mixParams: [AVMutableAudioMixInputParameters] = []
        for i in 0..<n {
            let asset = assets[i]
            guard let srcV = asset.tracks(withMediaType: .video).first,
                  let vt = comp.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { return false }
            let srcRange = CMTimeRange(start: ct(segments[i].start),
                                       duration: ct(outDurs[i] * Double(max(segments[i].speed, 0.1))))
            do {
                try vt.insertTimeRange(srcRange, of: srcV, at: ct(pos[i]))
                if abs(Double(segments[i].speed) - 1.0) > 0.001 {
                    vt.scaleTimeRange(
                        CMTimeRange(start: ct(pos[i]), duration: srcRange.duration),
                        toDuration: ct(outDurs[i]))
                }
            } catch {
                NSLog("vedit multi insert %d failed: %@", i, error.localizedDescription)
                return false
            }
            vTracks.append(vt)
            if !muted, let srcA = asset.tracks(withMediaType: .audio).first,
               let at = comp.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                do {
                    try at.insertTimeRange(srcRange, of: srcA, at: ct(pos[i]))
                    if abs(Double(segments[i].speed) - 1.0) > 0.001 {
                        at.scaleTimeRange(
                            CMTimeRange(start: ct(pos[i]), duration: srcRange.duration),
                            toDuration: ct(outDurs[i]))
                    }
                    let params = AVMutableAudioMixInputParameters(track: at)
                    params.setVolume(segments[i].mutedSegment ? 0 : 1, at: ct(pos[i]))
                    mixParams.append(params)
                } catch {
                    NSLog("vedit multi audio insert %d failed: %@", i, error.localizedDescription)
                }
            }
        }

        // 5) 视频合成指令：solo 区 + 重叠区（双层 opacity 斜坡交叉淡化）
        var size = assets.first?.tracks(withMediaType: .video).first?.naturalSize
            ?? CGSize(width: 1080, height: 1920)
        size = CGSize(width: abs(size.width).rounded(.down) / 2 * 2,
                      height: abs(size.height).rounded(.down) / 2 * 2)

        func layerFor(_ i: Int, startT: Double, endT: Double,
                      fadeHead: Bool, fadeTail: Bool) -> AVMutableVideoCompositionLayerInstruction {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTracks[i])
            layer.setTransform(CGAffineTransform.identity, at: ct(startT))
            if fadeHead {
                layer.setOpacityRamp(
                    fromStartOpacity: 0.0, toEndOpacity: 1.0,
                    timeRange: CMTimeRange(start: ct(startT), duration: ct(fadeLen)))
            } else {
                layer.setOpacity(1.0, at: ct(startT))
            }
            if fadeTail {
                layer.setOpacityRamp(
                    fromStartOpacity: 1.0, toEndOpacity: 0.0,
                    timeRange: CMTimeRange(start: ct(endT - fadeLen), duration: ct(fadeLen)))
            } else {
                layer.setOpacity(1.0, at: ct(endT))
            }
            return layer
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for i in 0..<n {
            let segStart = pos[i]
            let segEnd = pos[i] + outDurs[i]
            let headFade = (i > 0 && segments[i - 1].fade)
            let tailFade = (i + 1 < n && segments[i].fade)
            let soloStart = segStart + (headFade ? fadeLen : 0)
            let soloEnd = segEnd - (tailFade ? fadeLen : 0)
            // solo 区
            if soloEnd > soloStart {
                let ins = AVMutableVideoCompositionInstruction()
                ins.timeRange = CMTimeRange(start: ct(soloStart), end: ct(soloEnd))
                ins.layerInstructions = [layerFor(i, startT: soloStart, endT: soloEnd,
                                                  fadeHead: false, fadeTail: false)]
                instructions.append(ins)
            }
            // 与上一段的重叠区（双层交叉淡化）
            if headFade {
                let ins = AVMutableVideoCompositionInstruction()
                ins.timeRange = CMTimeRange(start: ct(segStart), end: ct(segStart + fadeLen))
                ins.layerInstructions = [
                    layerFor(i - 1, startT: segStart, endT: segStart + fadeLen,
                             fadeHead: false, fadeTail: true),
                    layerFor(i, startT: segStart, endT: segStart + fadeLen,
                             fadeHead: true, fadeTail: false)
                ]
                instructions.append(ins)
            }
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.instructions = instructions

        // 6) 导出（audioMix 挂在 export session 上，官方链路）
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent("vedit_multi_\(Int(Date().timeIntervalSince1970)).mp4")
        guard let session = AVAssetExportSession(
            asset: comp, presetName: AVAssetExportPresetHighestQuality
        ) else { return false }
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = composition
        if !mixParams.isEmpty {
            let aMix = AVMutableAudioMix()
            aMix.inputParameters = mixParams
            session.audioMix = aMix
        }
        let completed: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pollProgress(session: session, untilDone: { cont.resume(returning: session.status == .completed) },
                         scale: 0.95, progress: progress)
            session.exportAsynchronously {}
        }
        guard completed else { return false }
        DispatchQueue.main.async { progress(1.0) }
        PHLibraryService.saveVideo(outURL)
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
