import AppKit
import SwiftUI

enum ColorTokens {
    /// 品牌强调色：克制的靛蓝，随浅/深色外观自动切换。
    /// 用动态 NSColor，让 SwiftUI 按当前 appearance 解析，无需在各处读取 colorScheme。
    static let accent = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.58, green: 0.68, blue: 1.00, alpha: 1) // #94ADFF
                : NSColor(srgbRed: 0.29, green: 0.43, blue: 0.98, alpha: 1) // #4A6EFA
        }
    )

    /// 完成度“电池填充”使用的绿色，随浅/深色外观自动切换。
    static let completionGreen = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.34, green: 0.80, blue: 0.50, alpha: 1) // #57CC80
                : NSColor(srgbRed: 0.18, green: 0.62, blue: 0.38, alpha: 1) // #2E9E61
        }
    )

    static let accentSoft = accent.opacity(0.14)
    static let accentLight = accent.opacity(0.10)
    static let checkboxIncomplete = Color.secondary
    static let checkboxComplete = accent
    static let sectionHeader = Color.secondary

    /// 进度环描边使用的玻璃折射渐变：高光 → 半透明 → 阴影，保留品牌蓝。
    static let accentGradient = LinearGradient(
        colors: [
            accent.opacity(0.95),
            accent.opacity(0.30),
            accent.opacity(0.75)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
