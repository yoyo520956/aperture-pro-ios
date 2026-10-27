import SwiftUI
import UIKit

/// 中式审美设计 token · 宣纸 / 墨 / 青黛 / 朱砂
/// 原则：意境留白 · 含蓄克制 · 低饱和 · 4pt 网格 · 圆角阶梯
enum CNTheme {
    // MARK: 色（宣纸米白 · 墨 · 青黛 · 朱砂 · 云雾灰）

    /// 宣纸米白 · 页面底
    static let paper = adaptive(0xF7F4EF, 0x111315)
    /// 宣纸深一档 · 卡片 / 分区
    static let paperDeep = adaptive(0xEFE9DE, 0x1C2024)
    /// 墨 · 主文字
    static let ink = adaptive(0x1F1F1F, 0xF2F0EB)
    /// 次墨 · 副文字
    static let inkSub = adaptive(0x5A6472, 0xA7ADB4)
    /// 淡墨 · 占位 / 禁用
    static let inkFaint = adaptive(0x9AA3AD, 0x666C74)
    /// 宣纸纹分割线
    static let line = adaptive(0xE5E0D4, 0x2A3037)
    /// 青黛 · 结构强调 / 链接
    static let indigo = adaptive(0x3E5C6B, 0x7FA8BC)
    /// 朱砂 · 唯一高饱和点缀（克制使用）
    static let cinnabar = adaptive(0xB5483F, 0xC86A5E)
    /// 云雾灰 · 辅助
    static let cloud = adaptive(0x8C9BA5, 0x8C9BA5)

    // MARK: 圆角阶梯（2/4/8/12/16/20，取 4 的因子档位）

    static let r2: CGFloat = 2
    static let r4: CGFloat = 4
    static let r8: CGFloat = 8
    static let r12: CGFloat = 12
    static let r16: CGFloat = 16
    static let r20: CGFloat = 20

    // MARK: 字号阶梯（Dynamic Type 基准）

    static let f10: Font = .system(size: 10, weight: .regular)
    static let f12: Font = .system(size: 12, weight: .regular)
    static let f14: Font = .system(size: 14, weight: .regular)
    static let f15: Font = .system(size: 15, weight: .regular)
    static let f17: Font = .system(size: 17, weight: .medium)
    static let f22: Font = .system(size: 22, weight: .semibold)
    static let f28: Font = .system(size: 28, weight: .semibold)

    // MARK: 间距（4pt 网格）

    static let sp4: CGFloat = 4
    static let sp8: CGFloat = 8
    static let sp12: CGFloat = 12
    static let sp16: CGFloat = 16
    static let sp24: CGFloat = 24
    static let sp32: CGFloat = 32

    // MARK: 相机页（深色场景 · 朱砂点缀）

    static let shutterRing = Color.white.opacity(0.25)
    static let shutterFill = Color.white
    static let recordDot = cinnabar

    // MARK: 通用页面容器

    static func pageBackground() -> some View {
        CNTheme.paper.ignoresSafeArea()
    }

    static func card() -> some View {
        RoundedRectangle(cornerRadius: r12)
            .fill(CNTheme.paperDeep)
    }

    /// 分段式模式切换 chip
    struct ModeChip: View {
        let title: String
        let icon: String
        let active: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: sp4) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                    Text(title)
                        .font(CNTheme.f10)
                }
                .foregroundStyle(active ? .white : CNTheme.inkSub)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: CNTheme.r12)
                        .fill(active ? CNTheme.indigo : CNTheme.paperDeep)
                )
            }
        }
    }

    private static func hex(_ v: UInt32) -> UIColor {
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// 深浅双档自动切换色
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        let c = UIColor { trait in
            trait.userInterfaceStyle == .dark ? hex(dark) : hex(light)
        }
        return Color(uiColor: c)
    }
}
