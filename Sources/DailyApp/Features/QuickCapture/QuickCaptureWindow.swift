import AppKit
import DailyCore
import SwiftUI

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Floating glass quick-capture window invoked by global shortcut Command-Shift-N.
@MainActor
final class QuickCaptureWindow {
    private var window: NSPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let existing = window, existing.isVisible {
            existing.appearance = NSAppearance.from(colorSchemeMode: model.colorSchemeMode)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance.from(colorSchemeMode: model.colorSchemeMode)
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.center()

        let host = NSHostingView(
            rootView: QuickCaptureContent(model: model, onDismiss: { [weak self] in
                self?.window?.orderOut(nil)
            })
        )
        panel.contentView = host
        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }
}

// MARK: - SwiftUI Content

private struct QuickCaptureContent: View {
    @Bindable var model: AppModel
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var isAdding = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("⚡ 快速添加")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 16)

            HStack(spacing: 8) {
                Text("📝")
                    .font(.system(size: 15))

                TextField("输入任务标题，回车添加", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("新任务标题")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassModule(interactive: true, cornerRadius: 12)
        }
        .padding(20)
        .frame(width: 400, height: 140)
        .preferredColorScheme(model.colorSchemeMode.swiftUIColorScheme)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(KeyEquivalent.escape) {
            onDismiss()
            return KeyPress.Result.handled
        }
    }

    private func submit() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAdding else { return }
        isAdding = true
        Task { @MainActor in
            await model.add(TaskDraft(title: text))
            isAdding = false
            title = ""
            onDismiss()
        }
    }
}
