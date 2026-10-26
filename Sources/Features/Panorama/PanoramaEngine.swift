import AVFoundation
import CoreGraphics
import UIKit

/// 全景引擎：横滑相机时连续抓帧，按 25% 重叠交叉淡化横向拼接
final class PanoramaEngine {
    private var frames: [CGImage] = []
    private let ciContext = CIContext()
    let targetCount = 12
    private let overlapRatio: CGFloat = 0.25
    private let maxFrameHeight: CGFloat = 900

    var isCollecting: Bool { frames.count < targetCount }

    var capturedCount: Int { frames.count }

    func reset() {
        frames = []
    }

    /// 由相机帧回调驱动
    func addFrame(_ buffer: CVPixelBuffer) {
        guard frames.count < targetCount else { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let scale = min(1, maxFrameHeight / CGFloat(ci.extent.height))
        let targetW = Int(CGFloat(cg.width) * scale)
        let targetH = Int(CGFloat(cg.height) * scale)
        let cropRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        guard let scaled = cropRect == CGRect(origin: .zero, size: cg.size)
            ? cg
            : cg.cropping(to: cropRect)
        else { return }
        frames.append(scaled)
    }

    /// 横向拼接成全景长图
    func stitch() -> Data? {
        guard frames.count >= 4 else { return nil }
        let w = frames[0].width
        let h = frames[0].height
        let step = Int(CGFloat(w) * (1 - overlapRatio))
        let totalW = step * (frames.count - 1) + w
        let overlapW = w - step

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalW, height: h))
        let ui = renderer.image { ctx in
            let cg = ctx.cgContext
            if let first = frames.first {
                cg.draw(first, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            for i in 1..<frames.count {
                let img = frames[i]
                guard let mask = gradientMask(width: w, height: h, overlapWidth: overlapW) else { continue }
                cg.saveGState()
                cg.clip(to: mask, mask: nil, options: .premultipliedLast, operation: .copy)
                cg.draw(img, in: CGRect(x: i * step, y: 0, width: w, height: h))
                cg.restoreGState()
            }
        }
        return ui.jpegData(compressionQuality: 0.9)
    }

    /// 左侧重叠区黑→白渐变蒙版（黑=透 白=实）
    private func gradientMask(width: Int, height: Int, overlapWidth: Int) -> CGImage? {
        let mR = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let img = mR.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let colors = [UIColor.black.cgColor, UIColor.white.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let start = CGPoint(x: 0, y: 0)
                let end = CGPoint(x: CGFloat(overlapWidth), y: 0)
                cg.drawLinearGradient(grad, start: start, end: end, options: [])
            }
        }
        return img.cgImage
    }
}
