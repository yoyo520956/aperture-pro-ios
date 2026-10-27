import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// Homography 拼接内核：Harris 角点 + 方向量化描述子 + RANSAC 单应矩阵（DLT 4 点最小解）
/// 供 全景（横轴）/ 长图（纵轴）/ 夜景多帧对齐 共用。
///
/// 坐标约定：所有仿射都在「归一化单位方格」空间（帧宽高各缩到 1）：
/// 点 p=(x,y)∈[0,1]²，仿射 6 元素 [m00 m01 m02; m10 m11 m12]，
/// 变换：x' = m00*x + m01*y + m02。
/// 调用方拿到 affine 后按「帧真实像素宽/高」把归一化结果乘回像素即可。
enum HomographyStitcher {
    enum Axis { case horizontal, vertical }

    // MARK: - 对齐结果

    struct HAlignResult {
        /// 新帧 b（归一化）→ 旧帧 a（归一化）的平移+尺度仿射
        var affine: [Float]
        var inlierRatio: Float
        var inliers: Int
        var matched: Bool
    }

    static let identityAffine: [Float] = [1, 0, 0, 0, 1, 0]

    /// 把新帧 b 映射到旧帧 a 坐标系。
    /// 横轴：b 右移 tx 后与 a 重合（tx>0）；纵轴：b 下移 ty（ty>0）。
    /// 全失败返回 nil（调用方回退旧算法）。
    static func align(_ a: CGImage, _ b: CGImage, axis: Axis = .horizontal) -> HAlignResult? {
        let n = min(256, a.width, a.height, b.width, b.height)
        guard n >= 64 else { return nil }
        guard let ga = grayscale(a, n: n),
              let gb = grayscale(b, n: n) else { return nil }

        let fa = harrisCorners(ga, n: n)
        let fb = harrisCorners(gb, n: n)
        if fa.count >= 32, fb.count >= 32 {
            let matches = nearestMatches(fa, fb, threshold: 0.30)
            if matches.count >= 12 {
                // 归一化坐标（除以 n）
                let pa = matches.map { [Double(fa[$0.0].x) / Double(n), Double(fa[$0.0].y) / Double(n)] }
                let pb = matches.map { [Double(fb[$0.1].x) / Double(n), Double(fb[$0.1].y) / Double(n)] }
                // 求 H 使 H·pb ≈ pa（b→a）
                if let H = ransacHomography(src: pb, dst: pa, iters: 400, tol: 0.02, minInliers: 12) {
                    let inl = countInliers(src: pb, dst: pa, H: H, tol: 0.03).count
                    let ratio = Float(inl) / Float(matches.count)
                    if ratio >= 0.30 {
                        return HAlignResult(affine: toAffine(H), inlierRatio: ratio, inliers: inl, matched: true)
                    }
                }
            }
        }
        // 特征路线失败/歧义 → 轴带 MAD 搜索兜底
        return axis == .horizontal ? horizontalSearch(ga, gb, n) : verticalSearch(ga, gb, n)
    }

    // MARK: - 回退：轴带 MAD 搜索（降采样 4:1）

    /// 横轴：a 右带 [n-ov, n) ↔ b 左带 [0, ov)，搜最佳重叠 ov∈[0.2n, 0.6n]
    static func horizontalSearch(_ ga: [UInt8], _ gb: [UInt8], _ n: Int) -> HAlignResult? {
        var best: (score: Double, ov: Int)?
        var ov = n / 5
        let hi = 3 * n / 5
        while ov <= hi {
            let s = bandMAD(ga, gb, n, ov: ov, vertical: false)
            if best == nil || s < best!.score { best = (s, ov) }
            ov += max(4, n / 40)
        }
        guard let b = best, b.ov >= 8 else { return nil }
        // 归一化 tx = (n - ov) / n
        let tx = Double(n - b.ov) / Double(n)
        return HAlignResult(affine: [1, 0, Float(tx), 0, 1, 0], inlierRatio: 0.5, inliers: 0, matched: true)
    }

    /// 纵轴：a 下带 ↔ b 上带
    static func verticalSearch(_ ga: [UInt8], _ gb: [UInt8], _ n: Int) -> HAlignResult? {
        var best: (score: Double, ov: Int)?
        var ov = n / 5
        let hi = 3 * n / 5
        while ov <= hi {
            let s = bandMAD(ga, gb, n, ov: ov, vertical: true)
            if best == nil || s < best!.score { best = (s, ov) }
            ov += max(4, n / 40)
        }
        guard let b = best, b.ov >= 8 else { return nil }
        let ty = Double(n - b.ov) / Double(n)
        return HAlignResult(affine: [1, 0, 0, 0, 1, Float(ty)], inlierRatio: 0.5, inliers: 0, matched: true)
    }

    private static func bandMAD(_ ga: [UInt8], _ gb: [UInt8], _ n: Int, ov: Int, vertical: Bool) -> Double {
        guard ov > 8 else { return .greatestFiniteMagnitude }
        var sum = 0.0, cnt = 0.0
        if vertical {
            var r = n - ov
            while r < n - 4 {
                var c = 4
                while c < n - 4 {
                    sum += Double(abs(Int32(ga[r * n + c]) - Int32(gb[(r - (n - ov)) * n + c])))
                    cnt += 1
                    c += 4
                }
                r += 4
            }
        } else {
            var c = n - ov
            while c < n - 4 {
                var r = 4
                while r < n - 4 {
                    sum += Double(abs(Int32(ga[r * n + c]) - Int32(gb[r * n + (c - (n - ov))])))
                    cnt += 1
                    r += 4
                }
                c += 4
            }
        }
        return cnt > 0 ? sum / cnt : .greatestFiniteMagnitude
    }

    // MARK: - 灰度化（降采样 n×n）

    static func grayscale(_ img: CGImage, n: Int) -> [UInt8]? {
        guard let ctx = CGContext(
            data: nil, width: n, height: n,
            bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: n * n)
        for i in 0..<(n * n) { out[i] = ptr[i * 4] }
        return out
    }

    // MARK: - Harris 角点 + 紧凑描述子

    struct Feature {
        var x: Int
        var y: Int
        var r: Double   // Harris 响应（越大越好）
        var desc: [Float] // 8 维方向箱（已归一化）
    }

    static func harrisCorners(_ g: [UInt8], n: Int) -> [Feature] {
        let step = 4
        var feats: [Feature] = []
        var y = 4
        while y < n - 4 {
            var x = 4
            while x < n - 4 {
                let i = y * n + x
                let gx = Double(Int32(g[i + 1]) - Int32(g[i - 1])) * 0.5
                let gy = Double(Int32(g[i + n]) - Int32(g[i - n])) * 0.5
                let gxy = Double(g[i - n - 1] + g[i + n + 1] - g[i - n + 1] - g[i + n - 1]) * 0.25
                let R = gx * gx * gy * gy - 0.4 * gxy * gxy
                if R > 250 {
                    feats.append(Feature(x: x, y: y, r: R, desc: descriptor(g, n: n, cx: x, cy: y)))
                }
                x += step
            }
            y += step
        }
        feats.sort { $0.r > $1.r }
        return Array(feats.prefix(300))
    }

    /// 8 方向梯度箱（5×5 邻域，强度累加，L2 归一化）
    private static func descriptor(_ g: [UInt8], n: Int, cx: Int, cy: Int) -> [Float] {
        var bins = [Float](repeating: 0, count: 8)
        var dy = -3
        while dy <= 3 {
            var dx = -3
            while dx <= 3 {
                if dx == 0 && dy == 0 { dx = 1; continue }
                let px = cx + dx, py = cy + dy
                if 0 < px, px < n - 1, 0 < py, py < n - 1 {
                    let gx = Double(Int32(g[py * n + px + 1]) - Int32(g[py * n + px - 1])) * 0.5
                    let gyv = Double(Int32(g[(py + 1) * n + px]) - Int32(g[(py - 1) * n + px])) * 0.5
                    let mag = (gx * gx + gyv * gyv).squareRoot()
                    if mag > 4 {
                        let ang = atan2(gyv, gx) + .pi / 8
                        let bin = Int((ang / (2 * .pi / 8)).rounded()) % 8
                        let strength = Float(mag > 24 ? 3.0 : (mag > 12 ? 2.0 : 1.0))
                        bins[bin] += strength
                    }
                }
                dx += 1
            }
            dy += 1
        }
        var norm: Float = 0
        for b in bins { norm += b * b }
        let inv = norm > 0 ? 1 / norm.squareRoot() : 0
        return bins.map { $0 * inv }
    }

    // MARK: - 最近邻匹配（带阈值）

    static func nearestMatches(_ a: [Feature], _ b: [Feature], threshold: Float) -> [(Int, Int)] {
        var res: [(Int, Int)] = []
        let t2 = threshold * threshold
        for i in a.indices {
            var bestJ = -1
            var bestD = Float.greatestFiniteMagnitude
            for j in b.indices {
                var d: Float = 0
                for k in 0..<8 {
                    let dd = a[i].desc[k] - b[j].desc[k]
                    d += dd * dd
                }
                if d < bestD { bestD = d; bestJ = j }
            }
            if bestJ >= 0, bestD <= t2 {
                res.append((i, bestJ))
            }
        }
        return res
    }

    // MARK: - RANSAC 单应（4 点 DLT 最小解 + 内点重解）

    /// 求 H 使 H·src ≈ dst（归一化齐次点 [x y 1]）
    static func ransacHomography(
        src: [[Double]], dst: [[Double]],
        iters: Int, tol: Double, minInliers: Int
    ) -> [Double]? {
        let n = src.count
        guard n >= 8 else { return nil }
        var bestInliers: [Int] = []
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<iters {
            var idx = [Int]()
            while idx.count < 4 {
                let k = Int(rng.next() % UInt64(n))
                if !idx.contains(k) { idx.append(k) }
            }
            let pts = idx.map { (src[$0], dst[$0]) }
            guard let H = dltHomography4pts(pts) else { continue }
            let inl = countInliers(src: src, dst: dst, H: H, tol: tol)
            if inl.count > bestInliers.count { bestInliers = inl }
        }
        guard bestInliers.count >= minInliers else { return nil }
        let pairs = src.enumerated().map { ($0.1, dst[$0.0]) }
        return dltHomographyAll(pairs, idx: bestInliers)
    }

    private static func countInliers(
        src: [[Double]], dst: [[Double]], H: [Double], tol: Double
    ) -> [Int] {
        var out: [Int] = []
        for i in 0..<src.count {
            let x = src[i][0], y = src[i][1]
            let w = H[6] * x + H[7] * y + H[8]
            guard abs(w) > 1e-9 else { continue }
            let px = (H[0] * x + H[1] * y + H[2]) / w
            let py = (H[3] * x + H[4] * y + H[5]) / w
            let dx = px - dst[i][0], dy = py - dst[i][1]
            if dx * dx + dy * dy < tol * tol { out.append(i) }
        }
        return out
    }

    /// 4 点最小解：8×8 高斯消元（齐次，h8=1 回代）
    private static func dltHomography4pts(_ pts: [([Double], [Double])]) -> [Double]? {
        var A = [[Double]]()
        A.reserveCapacity(8)
        for (s, d) in pts {
            A.append([-s[0], -s[1], -1, 0, 0, 0, d[0] * s[0], d[0] * s[1], d[0]])
            A.append([0, 0, 0, -s[0], -s[1], -1, d[1] * s[0], d[1] * s[1], d[1]])
        }
        return gaussSolve8x9(A)
    }

    /// 全内点最小二乘（9×9 正规方程 → 约化 8×8 线性组）
    private static func dltHomographyAll(_ pairs: [([Double], [Double])], idx: [Int]) -> [Double] {
        var M = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 9)
        for i in idx {
            let s = pairs[i].0, d = pairs[i].1
            let rows: [[Double]] = [
                [-s[0], -s[1], -1, 0, 0, 0, d[0] * s[0], d[0] * s[1], d[0]],
                [0, 0, 0, -s[0], -s[1], -1, d[1] * s[0], d[1] * s[1], d[1]]
            ]
            for row in rows {
                for a in 0..<9 {
                    for b in 0..<9 {
                        M[a][b] += row[a] * row[b]
                    }
                }
            }
        }
        var A = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var rhs = [Double](repeating: 0, count: 8)
        for r in 0..<8 {
            for c in 0..<8 { A[r][c] = M[r][c] }
            rhs[r] = -M[r][8]
        }
        guard let h = gaussSolveLinear(A, rhs) else { return [1, 0, 0, 0, 1, 0, 0, 0, 1] }
        return h + [1.0]
    }

    /// 8×8 高斯-约当
    private static func gaussSolveLinear(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = A.count
        guard A[0].count == n, b.count == n else { return nil }
        var M = A.enumerated().map { i, row in row + [b[i]] }
        for col in 0..<n {
            var piv = col
            for r in (col + 1)..<n where abs(M[r][col]) > abs(M[piv][col]) { piv = r }
            guard abs(M[piv][col]) > 1e-12 else { return nil }
            M.swapAt(col, piv)
            let inv = 1 / M[col][col]
            for c in col..<n + 1 { M[col][c] *= inv }
            for r in 0..<n where r != col {
                let f = M[r][col]
                if f != 0 {
                    for c in col..<n + 1 { M[r][c] -= f * M[col][c] }
                }
            }
        }
        return (0..<n).map { M[$0][n] }
    }

    /// 8×9 齐次回代（h8=1）
    private static func gaussSolve8x9(_ A: [[Double]]) -> [Double]? {
        let n = A.count
        guard n == 8, A[0].count == 9 else { return nil }
        var M = A
        for col in 0..<8 {
            var piv = col
            for r in (col + 1)..<8 where abs(M[r][col]) > abs(M[piv][col]) { piv = r }
            guard abs(M[piv][col]) > 1e-12 else { continue }
            M.swapAt(col, piv)
            for r in (col + 1)..<8 {
                let f = M[r][col] / M[piv][col]
                for c in col..<9 { M[r][c] -= f * M[piv][c] }
            }
        }
        var h = [Double](repeating: 0, count: 8)
        for r in stride(from: 7, through: 0, by: -1) {
            var s = M[r][8]
            for c in (r + 1)..<8 { s -= M[r][c] * h[c] }
            guard abs(M[r][r]) > 1e-12 else { return nil }
            h[r] = s / M[r][r]
        }
        return h
    }

    // MARK: - 齐次/仿射工具

    /// 单应 → 平移+尺度仿射（归一化空间）
    static func toAffine(_ H: [Double]) -> [Float] {
        let s = (H[0] + H[4]) * 0.5
        return [Float(s), 0, Float(H[2]), 0, Float(s), Float(H[5])]
    }

    /// 点应用（归一化坐标）
    static func applyAffine(_ m: [Float], _ x: Double, _ y: Double) -> (Double, Double) {
        (Double(m[0]) * x + Double(m[1]) * y + Double(m[2]),
         Double(m[3]) * x + Double(m[4]) * y + Double(m[5]))
    }

    /// 仿射合成 C = A∘B（B 先作用于点）
    static func composeAffine(_ a: [Float], _ b: [Float]) -> [Float] {
        [
            a[0] * b[0] + a[1] * b[3], a[0] * b[1] + a[1] * b[4], a[0] * b[2] + a[1] * b[5],
            a[3] * b[0] + a[4] * b[3], a[3] * b[1] + a[4] * b[4], a[3] * b[2] + a[4] * b[5]
        ]
    }
}

// MARK: - 可复现 RNG

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
