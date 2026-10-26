import AVFoundation
import CoreImage
import UIKit

/// 延时摄影引擎：相机逐帧按固定间隔抽帧，叠加时间码后写成视频
/// 帧经 AVAssetWriterInputPixelBufferAdaptor 写入；时间码文本只在秒数变化时重绘
final class TimelapseEngine {
    private var writer: AVAssetWriter?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var lastWriteTime: Double = -1
    private var frameIndex: Int64 = 0
    private var outName = ""
    private var outW: Int = 0
    private var outH: Int = 0

    var isWriting: Bool { writer != nil }
    var capturedFrames: Int { Int(frameIndex) }
    /// 已录制的真实时间跨度（秒）
    var elapsed: Double { lastWriteTime < 0 ? 0 : (lastWriteTime - startTime) }
    private var startTime: Double = -1
    private let frameInterval: Double = 0.5
    private let ciContext = CIContext()

    private var lastSecondText: String = ""
    private var lastSecondImage: CGImage?

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
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealtime = true
        guard w.canInput(input) else { return }
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(width),
            kCVPixelBufferHeightKey as String: Int(height)
        ]
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: poolAttrs)
        w.add(input)
        writer = w
        adaptor = ad
        w.startWriting()
        w.startSession(atSourceTime: .zero)
        outName = name
        outW = Int(width)
        outH = Int(height)
        lastWriteTime = -1
        frameIndex = 0
        startTime = CMAbsoluteTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        lastSecondText = ""
        lastSecondImage = nil
    }

    /// 由相机帧回调驱动，内部按 frameInterval 抽帧，pts 单调递增
    func addFrame(_ sample: CMSampleBuffer) {
        guard let writer, let adaptor, writer.status == .writing else { return }
        guard let pb = CVPixelBufferGetPixelBufferFromSampleBuffer(sample) else { return }
        let now = CMAbsoluteTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        guard lastWriteTime < 0 || now - lastWriteTime >= frameInterval else { return }
        lastWriteTime = now

        guard adaptor.isReadyForMoreMediaData else { return }
        let pts = CMTime(seconds: Double(frameIndex) * frameInterval, preferredTimescale: 1_000_000)
        frameIndex += 1

        // 输出像素池（BGRA）
        guard let pool = adaptor.pixelBufferPool else { return }
        var outPB: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outPB)
        guard var pixel = outPB else { return }
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }

        // 画帧底
        let w = Int32(CVPixelBufferGetWidth(pixel))
        let h = Int32(CVPixelBufferGetHeight(pixel))
        guard let base = CVPixelBufferGetBaseAddress(pixel) else { return }
        let bpr = Int32(CVPixelBufferGetBytesPerRow(pixel))
        let ctx = CGContext(
            data: base, width: Int(w), height: Int(h),
            bitsPerComponent: 8, bytesPerRow: Int(bpr),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        guard let ctx else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        let cg = ciContext.createCGImage(ci, from: ci.extent)
        if let cg {
            let scale = CGFloat(w) / CGFloat(cg.width)
            let dw = Int(cg.width * scale)
            let dh = Int(cg.height * scale)
            ctx.draw(cg, in: CGRect(x: 0, y: Int(h) - dh, width: dw, height: dh))
        }
        // 时间码（每秒重绘一次）
        let elapsedNow = now - startTime
        let second = Int(elapsedNow)
        let text = String(format: "00:%02d:%02d", second / 60, second % 60)
        if text != lastSecondText {
            lastSecondText = text
            lastSecondImage = renderTimecode(text, size: CGSize(width: CGFloat(w), height: CGFloat(h)))
        }
        if let tc = lastSecondImage {
            ctx.draw(tc, in: CGRect(x: 24, y: Int(h) - tc.height - 24, width: tc.width, height: tc.height))
        }
        adaptor.append(pixel, withPresentationTime: pts)
    }

    func stop() -> String? {
        guard let writer, let adaptor else { return nil }
        adaptor.markAsFinished()
        let w = writer
        w?.finishWriting { [weak w] in
            if let w, let err = w.error {
                NSLog("timelapse writer error: \(err.localizedDescription)")
            }
        }
        let name = outName
        self.writer = nil
        self.adaptor = nil
        return name
    }

    // MARK: - 时间码渲染（黑底青黛字，左下角）

    private func renderTimecode(_ text: String, size: CGSize) -> CGImage? {
        let fontSize: CGFloat = max(28, size.width / 22)
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .paragraphStyle: para
        ]
        let str = text as NSString
        let textSize = str.boundingRect(
            with: CGSize(width: 400, height: fontSize * 2),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        ).size
        let imgW = Int(textSize.width) + 24
        let imgH = Int(fontSize * 1.6)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imgW, height: imgH))
        let ui = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            cg.addRoundedRect(in: CGRect(x: 0, y: 0, width: imgW, height: imgH), cornerRadius: 8, transform: nil)
            cg.fillPath()
            str.draw(
                in: CGRect(x: 12, y: (imgH - Int(fontSize)) / 2, width: imgW - 24, height: Int(fontSize * 1.4)),
                withAttributes: attrs
            )
        }
        return ui.cgImage
    }
}
