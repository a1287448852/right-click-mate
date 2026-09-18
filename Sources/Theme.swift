import Cocoa

/// 设计令牌。
///
/// 数值来自 Pinguo / Apple 设计系统（colors_and_type.css、css.json），
/// 配合 Apple HIG 的语义色，深色模式由系统自动跟随。
enum Theme {

    // MARK: - 半径
    // 设计系统 radius = 1.2rem ≈ 19.2px。原生控件的尺寸比 Web 小，
    // 按比例收敛到卡片 12 / 控件 8，保持同样的"软"观感。

    static let radiusCard: CGFloat = 12
    static let radiusControl: CGFloat = 8
    static let radiusGlass: CGFloat = 14

    // MARK: - 间距
    // 设计系统 scale: 4, 8, 12, 16, 24, 32, 48, 64

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let sidebarWidth: CGFloat = 208
    static let contentWidth: CGFloat = 560
    static let rowHeight: CGFloat = 32

    // MARK: - 颜色

    enum Palette {
        /// Pinguo Blue，设计系统里的品牌主色
        static let brand = NSColor(srgbRed: 0.00, green: 0.40, blue: 0.80, alpha: 1)

        /// System Blue，选中态与交互反馈
        static let accent = NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1)

        static let success = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        static let danger = NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)

        /// 卡片面。浅色纯白，深色 #1c1c1e，跟设计系统一致。
        static let card = NSColor(name: "card") { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                : NSColor.white
        }

        /// 分隔线 / 卡片边框 #e5e5ea ↔ #3a3a3c
        static let border = NSColor(name: "border") { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1)
        }

        /// 页面底色 #f2f2f7 ↔ #000000
        static let canvas = NSColor(name: "canvas") { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1)
                : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        }
    }

    // MARK: - 字体
    // 设计系统指定的 DM Sans / JetBrains Mono 是面向 Web 的。
    // 原生 App 用系统字体（SF Pro / SF Mono）才能跟 macOS 一致。

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// 数值、路径、哈希这类技术信息用等宽数字，对应设计系统里 JetBrains Mono 的意图。
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
