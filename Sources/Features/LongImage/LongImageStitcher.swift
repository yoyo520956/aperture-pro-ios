import UIKit

/// 长图拼接：把多张照片竖向接成一张长图（宽度归一 + 接缝对齐）
enum LongImageStitcher {
    static func stitch(_ images: [UIImage]) -> UIImage? {
        guard let first = images.first else { return nil }
        let targetW = images.reduce(0) { max($0, Int($1.size.width)) }
        let targetH = images.reduce(0) { $0 + Int((CGFloat($1.size.height) / $1.size.width) * CGFloat(targetW)) }
        guard targetW > 0, targetH > 0 else { return nil }
        _ = first
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: targetW, height: targetH),
            format: UIGraphicsImageRendererFormat()
        )
        var y: CGFloat = 0
        let result = renderer.image { ctx in
            for img in images {
                let w = targetW
                let h = Int(img.size.height / img.size.width * CGFloat(targetW))
                let r = CGRect(x: 0, y: y, width: w, height: h)
                ctx.cgContext.interpolationQuality = .high
                img.draw(in: r)
                y += h
            }
        }
        return result
    }

    static func stitchJPEGs(_ datas: [Data]) -> Data? {
        let imgs = datas.compactMap { UIImage(data: $0) }
        guard imgs.count >= 2 else { return nil }
        guard let img = stitch(imgs) else { return nil }
        return img.jpegData(compressionQuality: 0.85)
    }
}
