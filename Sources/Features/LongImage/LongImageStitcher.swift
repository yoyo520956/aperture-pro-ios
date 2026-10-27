import UIKit

/// 长图拼接：多张照片竖向接成一张长图
/// 相邻两张先实测纵向重叠区（降采样灰度逐列相关），重叠区做渐变缝合；
/// 匹配失败（无重叠/差异过大）时回退到直接堆叠
enum LongImageStitcher {
    private static let matchWidth = 72

    static func stitch(_ images: [UIImage]) -> UIImage? {
        guard images.count >= 2 else { return images.first }

        // 统一宽度（取最大，封顶 3000 防内存爆）
        let maxW = images.reduce(0) { max($0, Int($1.size.width)) }
        let normW = max(256, min(maxW, 3000))
        let scaled: [UIImage] = images.map { scaleWidth($0, normW) }

        // 逐对测重叠（normW 像素）：优先 homography 特征对齐，失败回退旧边缘相关
        var overlaps: [Int] = []
        for i in 1..<scaled.count {
            overlaps.append(measureOverlapHi(scaled[i - 1], scaled[i], width: normW))
        }

        // 总高
        var totalH = scaled[0].size.height
        for i in 1..<scaled.count {
            totalH += scaled[i].size.height - CGFloat(overlaps[i - 1])
        }
        guard totalH > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: CGFloat(normW), height: totalH), format: format
        )
        var y: CGFloat = 0
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            guard let first = scaled.first else { return }
            first.draw(in: CGRect(x: 0, y: 0, width: CGFloat(normW), height: first.size.height))
            y = first.size.height
            for i in 1..<scaled.count {
                let img = scaled[i]
                let h = img.size.height
                let ov = overlaps[i - 1]
                let startX = y - CGFloat(ov)
                if ov > 4 {
                    // 渐变蒙版：新图顶部 ov 像素 从透 → 实，接缝处混合新旧
                    if let mask = seamMask(width: normW, height: Int(h), overlap: ov) {
                        ctx.cgContext.saveGState()
                        ctx.cgContext.clip(to: mask, mask: nil, options: .premultipliedLast, operation: .copy)
                        img.draw(in: CGRect(x: 0, y: startX, width: normW, height: h))
                        ctx.cgContext.restoreGState()
                    } else {
                        img.draw(in: CGRect(x: 0, y: startX, width: normW, height: h))
                    }
                } else {
                    img.draw(in: CGRect(x: 0, y: y, width: normW, height: h))
                }
                y = startX + h
            }
        }
    }

    static func stitchJPEGs(_ datas: [Data]) -> Data? {
        let imgs = datas.compactMap { UIImage(data: $0) }
        guard imgs.count >= 2 else { return nil }
        guard let img = stitch(imgs) else { return nil }
        return img.jpegData(compressionQuality: 0.85)
    }

    // MARK: - 接缝蒙版（顶部 overlap 像素黑→白渐变，其余全白）

    private static func seamMask(width: Int, height: Int, overlap: Int) -> CGImage? {
        let mR = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let img = mR.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let colors = [UIColor.black.cgColor, UIColor.white.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let start = CGPoint(x: 0, y: 0)
                let end = CGPoint(x: 0, y: CGFloat(overlap))
                // 渐变只作用于顶部 overlap 条带（UIKit 坐标系 y 向下）
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: 0, width: width, height: overlap))
                cg.drawLinearGradient(grad, start: start, end: end, options: [])
                cg.restoreGState()
            }
        }
        return img.cgImage
    }

    // MARK: - 纵向重叠实测（优先 homography 特征对齐，回退逐列均值差）

    private static func measureOverlapHi(_ a: UIImage, _ b: UIImage, width: Int) -> Int {
        // homography：Harris 角点 + RANSAC 单应（纵轴）；1 - ty_norm 即重叠比例
        if let ca = a.cgImage, let cb = b.cgImage {
            if let r = HomographyStitcher.align(ca, cb, axis: .vertical), r.inlierRatio >= 0.3 {
                let ov = Int(CGFloat(width) * Double(1 - Double(r.affine[5])))
                return max(0, min(width, ov))
            }
        }
        return measureVerticalOverlap(a, b, width: width)
    }

    private static func measureVerticalOverlap(_ a: UIImage, _ b: UIImage, width: Int) -> Int {
        guard let ga = gray(a, targetWidth: matchWidth),
              let gb = gray(b, targetWidth: matchWidth),
              ga.height > 32, gb.height > 32
        else { return 0 }
        let ah = ga.height
        let bh = gb.height
        let maxOV = min(Int(CGFloat(bh) * 0.6), ah)
        guard maxOV > 8 else { return 0 }
        var bestOV = 0
        var bestScore = Double.infinity
        var ov = 4
        while ov <= maxOV {
            // b 顶部 ov 行 与 a 底部 ov 行 对齐：b[r] <-> a[ah - ov + r]
            var sumD: Double = 0
            var n: Double = 0
            let limit = min(ov, ah)
            for r in Swift.stride(from: 0, to: limit, by: 2) {
                for c in 0..<matchWidth where (c % 3) == 0 {
                    let va = ga[ah - ov + r, c]
                    let vb = gb[r, c]
                    sumD += Double(abs(Int(va) - Int(vb)))
                    n += 1
                }
            }
            guard n > 0 else { break }
            let score = sumD / n
            if score < bestScore {
                bestScore = score
                bestOV = ov
            }
            ov += 3
        }
        // 差异太大视为两张不同的图（直接堆叠）
        if bestScore > 36 { return 0 }
        return Int(CGFloat(bestOV) / CGFloat(matchWidth) * CGFloat(width))
    }

    // MARK: - 工具

    private static func scaleWidth(_ img: UIImage, _ targetW: Int) -> UIImage {
        let h = img.size.height / img.size.width * CGFloat(targetW)
        return UIGraphicsImageRenderer(
            size: CGSize(width: CGFloat(targetW), height: h)
        ).image { ctx in
            img.draw(in: CGRect(x: 0, y: 0, width: CGFloat(targetW), height: h))
        }
    }

    private struct GrayGrid {
        let width: Int
        let height: Int
        let data: [UInt8]
        subscript(r: Int, c: Int) -> UInt8 { data[r * width + c] }
    }

    private static func gray(_ img: UIImage, targetWidth: Int) -> GrayGrid? {
        let w = Int(img.size.width)
        let hPt = Int(img.size.height)
        guard w > 0, hPt > 8 else { return nil }
        let h = hPt * targetWidth / w
        guard h > 8 else { return nil }
        guard let cg = img.cgImage else { return nil }
        guard let ctx = CGContext(
            data: nil, width: targetWidth, height: h,
            bitsPerComponent: 8, bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetWidth, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: targetWidth * h)
        for i in 0..<(targetWidth * h) {
            out[i] = ptr[i * 4]
        }
        return GrayGrid(width: targetWidth, height: h, data: out)
    }
}
