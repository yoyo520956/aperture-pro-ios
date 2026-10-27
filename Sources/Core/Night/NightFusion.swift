import CoreImage
import CoreGraphics
import UIKit
import Foundation

/// 夜景多帧堆栈融合：EV 包围曝光帧 → 逐帧对齐到中间帧（homography 平移+尺度）
/// → 去 gamma → 线性域 Mantiuk 加权融合（高光给短曝、暗部给长曝，天然降噪提动态）→ 回 gamma
enum NightFusion {
    /// EV 包围序列（5 帧，中间为主帧）
    static let evOffsets: [Double] = [-2.0, -1.0, 0.0, 1.0, 2.0]

    /// 融合入口：frames（JPEG 解码后的 CIImage）与 evs 一一对应；返回融合结果（主帧尺寸）
    static func fuse(frames: [CIImage], evs: [Double]) -> CIImage? {
        guard frames.count >= 3, evs.count == frames.count else { return frames.first }
        let center = frames[frames.count / 2]
        let ctx = CIContext()
        guard let anchor = ctx.createCGImage(center, from: center.extent) else { return frames.first }

        // 1) 逐帧对齐到中间帧（homography 平移+尺度 → CI 仿射）
        var aligned: [CIImage] = []
        for (i, f) in frames.enumerated() {
            let fc = f.cropped(to: center.extent)
            if i == frames.count / 2 {
                aligned.append(fc)
                continue
            }
            guard let cg = ctx.createCGImage(fc, from: fc.extent) else {
                aligned.append(fc)
                continue
            }
            if let r = HomographyStitcher.align(cg, anchor, axis: .horizontal) {
                let w = Double(center.extent.width)
                let h = Double(center.extent.height)
                let s = Double(r.affine[0])
                let tx = Double(r.affine[2]) * w
                let ty = Double(r.affine[5]) * h
                let tf = CGAffineTransform(scaleX: s, y: s).concatenating(
                    CGAffineTransform(translationX: tx, y: ty)
                )
                aligned.append(fc.transformed(by: tf))
            } else {
                aligned.append(fc)
            }
        }

        // 2) Mantiuk 权重：w_i = (E_i·σ²)/(E_i·σ² + R²)，E_i = 2^EV
        let sigma = 0.2
        let R: Double = 0.15
        let weights = evs.map { e -> Double in
            let ex = pow(2.0, e)
            return ex * sigma * sigma / (ex * sigma * sigma + R * R)
        }

        // 3) 去 gamma（sRGB≈2.2）进线性域，逐帧加权平均，回 gamma
        func linearize(_ img: CIImage) -> CIImage {
            img.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 2.2])
        }
        func gammap(_ img: CIImage) -> CIImage {
            img.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.4545])
        }

        var acc = linearize(aligned[0])
        var wsum = weights[0]
        for i in 1..<aligned.count {
            let w = weights[i]
            // acc_new = acc*(wsum/wsumNew) + f_i*(w/wsumNew)（系数逐层归一，Σ=1）
            let wsumNew = wsum + w
            guard let f = CIFilter(name: "CIArithmeticFilter") else { break }
            f.setValue(linearize(aligned[i]), forKey: kCIInputImageKey)
            f.setValue(acc, forKey: kCIInputBackgroundImageKey)
            f.setValue(w / wsumNew, forKey: "inputA")
            f.setValue(wsum / wsumNew, forKey: "inputB")
            f.setValue(0.0, forKey: "inputC")
            f.setValue("addCompositing", forKey: "inputOperation")
            guard let outImg = f.outputImage else { break }
            acc = outImg.cropped(to: center.extent)
            wsum = wsumNew
        }
        var out = gammap(acc)
        out = out.cropped(to: center.extent)
        return out
    }

    /// 渲染融合结果为 JPEG Data
    static func renderJPEG(_ ci: CIImage, quality: Double = 0.9) -> Data? {
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: CGFloat(quality))
    }
}
