import AppKit
import SwiftUI

/// 让主窗口标题栏透明、内容顶满整窗（红绿灯与工具栏悬浮在内容背景之上）。
/// 注意：不设置 isOpaque=false / backgroundColor，否则整窗会透成桌面。
struct TransparentTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentTitlebarAccessor()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TransparentTitlebarAccessor: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        // SwiftUI 装配统一工具栏后可能重置标题栏外观，稍后重申一次以保险。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let window = self.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
