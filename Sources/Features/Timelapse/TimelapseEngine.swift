import AVFoundation

/// 延时摄影引擎：把相机逐帧回调按固定间隔抽帧，写成 30fps 慢速视频
final class TimelapseEngine {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var lastWriteTime: Double = -1
    private var frameIndex: Int64 = 0
    private var outName: String = ""
    var isWriting: Bool = false
    let frameInterval: Double = 0.5

    private static var mediaDir: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(width: Int32, height: Int32) {
        let name = "tl_\(Int(Date().timeIntervalSince1970)).mov"
        let outURL = Self.mediaDir.appendingPathComponent(name)
        guard let w = try? AVAssetWriter(outputURL: outURL, fileType: .mov) else { return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let in2 = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        in2.expectsMediaDataInRealtime = true
        guard w.canInput(in2) else { return }
        w.add(in2)
        writer = w
        input = in2
        w.startWriting()
        w.startSession()
        outName = name
        lastWriteTime = -1
        frameIndex = 0
        isWriting = true
    }

    /// 由相机帧回调驱动，内部按 frameInterval 抽帧，pts 单调递增
    func addFrame(_ sample: CMSampleBuffer) {
        guard isWriting, let input, input.isReadyForMoreMediaData else { return }
        let now = CMAbsoluteTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        guard lastWriteTime < 0 || now - lastWriteTime >= frameInterval else { return }
        lastWriteTime = now
        let pts = CMTime(seconds: Double(frameIndex) * frameInterval, preferredTimescale: 1_000_000)
        frameIndex += 1
        input.append(sample, withPresentationTime: pts)
    }

    func stop() -> String? {
        guard let writer, let input, isWriting else { return nil }
        isWriting = false
        input.markAsFinished()
        let w = writer
        w?.finishWriting { [weak w] in
            if let w, let err = w.error {
                NSLog("timelapse writer error: \(err.localizedDescription)")
            }
        }
        writer = nil
        input = nil
        return outName
    }
}
