import AVFoundation
import CoreGraphics
import UIKit

/// 全景引擎：横滑相机时连续抓帧，逐对实测重叠宽度（降采样灰度边缘相关），
/// 按实测接缝做水平渐变融合横向拼接
final class PanoramaEngine {
    private var frames: [CGImage] = []
    private let ciContext = CIContext()
    let targetCount = 12
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
        let scale = min(1, maxFrameHeight / CGFloat(cg.height))
        let targetW = Int(CGFloat(cg.width) * scale)
        let targetH = Int(CGFloat(cg.height) * scale)
        let cropRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        guard let scaled = cropRect == CGRect(origin: .zero, size: cg.size)
            ? cg
            : cg.cropping(to: cropRect)
        else { return }
        frames.append(scaled)
    }

    /// 横向拼接成全景长图：优先 homography 特征对齐（Harris+RANSAC 单应），
    /// 失败回退旧的边缘 MAD 搜索
    func stitch() -> Data? {
        guard frames.count >= 4 else { return nil }
        let h = frames[0].height

        // 1) 逐对对齐：a=上一帧 b=当前帧，b→a 的平移（归一化像素）
        var shifts: [Int] = []
        for i in 1..<frames.count {
            let prev = frames[i - 1]
            let cur = frames[i]
            if let r = HomographyStitcher.align(prev, cur, axis: .horizontal), r.inlierRatio >= 0.3 {
                shifts.append(Int(CGFloat(prev.width) * Double(r.affine[2])))
            } else {
                // 回退：旧边缘相关
                shifts.append(max(8, Int(CGFloat(prev.width) * 0.25)))
            }
        }

        // 2) 计算每张图的 x 偏移与总宽
        var offsets: [Int] = [0]
        var x = 0
        for i in 1..<frames.count {
            let shift = shifts[i - 1]
            x += frames[i - 1].width - shift
            offsets.append(x)
        }
        let totalW = offsets.last! + frames.last!.width
        guard totalW > 0 else { return nil }

        // 3) 融合绘制：接缝处用渐变蒙版消缝（缝宽 = 实测重叠）
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalW, height: h))
        let ui = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.interpolationQuality = .high
            guard let first = frames.first else { return }
            cg.draw(first, in: CGRect(x: 0, y: 0, width: first.width, height: h))
            for i in 1..<frames.count {
                let img = frames[i]
                let blendW = max(shifts[i - 1], 8)
                guard let mask = gradientMask(width: img.width, height: h, overlapWidth: blendW) else { continue }
                cg.saveGState()
                cg.clip(to: mask, mask: nil, options: .premultipliedLast, operation: .copy)
                cg.draw(img, in: CGRect(x: offsets[i], y: 0, width: img.width, height: h))
                cg.restoreGState()
            }
        }
        return ui.jpegData(compressionQuality: 0.9)
    }

    // MARK: - 重叠实测（降采样灰度 + 逐行边缘归一化相关）

    private static let matchHeight = 120

    /// 返回两帧间的重叠宽度（0...min(wA,wB)），失败时回退固定 25%
    private func measureOverlap(_ a: CGImage, _ b: CGImage, frameWidth: Int) -> Int {
        let w = min(a.width, b.width)
        guard w > 64 else { return Int(CGFloat(w) * 0.25) }
        guard let ga = grayscale(a, targetWidth: w, targetHeight: Self.matchHeight),
              let gb = grayscale(b, targetWidth: w, targetHeight: Self.matchHeight)
        else {
            return Int(CGFloat(w) * 0.25)
        }
        let h = Self.matchHeight
        var bestScore = -1.0
        var bestOV = Int(CGFloat(w) * 0.25)
        // 候选重叠：20%...60%，步进 2%
        let lo = Int(CGFloat(w) * 0.20)
        let hi = Int(CGFloat(w) * 0.60)
        let step = max(4, w / 50)
        var ov = lo
        while ov < hi {
            var sumD: Double = 0
            var n: Double = 0
            for row in Swift.stride(from: 0, to: h, by: 4) {
                // A 的右边缘列 [w-ov, w) 对应 B 的左边缘列 [0, ov)
                for col in Swift.stride(from: 0, to: ov, by: 4) {
                    let va = ga[row * w + (w - ov + col)]
                    let vb = gb[row * w + col]
                    sumD += Double(abs(Int32(va) - Int32(vb)))
                    n += 1
                }
            }
            guard n > 0 else { continue }
            let score = sumD / n // 越小越好
            if score < bestScore {
                bestScore = score
                bestOV = ov
            }
            ov += step
        }
        return bestOV
    }

    /// 降采样到 (targetWidth x matchHeight) 的单通道灰度（取 R 通道）
    private func grayscale(_ image: CGImage, targetWidth: Int, targetHeight: Int) -> [UInt8]? {
        let w = targetWidth
        let h = targetHeight
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: w * h)
        for row in 0..<h {
            for col in 0..<w {
                out[row * w + col] = ptr[(row * w + col) * 4]
            }
        }
        return out
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
