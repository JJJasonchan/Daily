import AppKit
import DailyCore
import SwiftUI

private final class QuickMemoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func focusEditor() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        if let editor = textEditor(in: contentView) {
            makeFirstResponder(editor)
        }
    }

    private func textEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { self.textEditor(in: $0) }.first
    }
}

/// Floating quick-memo window invoked by global shortcut Command-Shift-M.
@MainActor
final class QuickMemoWindow {
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

        let panel = QuickMemoPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 270),
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
            rootView: QuickMemoContent(model: model, onDismiss: { [weak self] in
                self?.window?.orderOut(nil)
            })
        )
        panel.contentView = host
        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.focusEditor()
    }
}

// MARK: - SwiftUI Content

private struct QuickMemoContent: View {
    @Bindable var model: AppModel
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("快速备忘录", systemImage: "square.and.pencil")
                    .font(.headline)
                    .labelStyle(QuickMemoTitleStyle())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭备忘录")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("写下想记住的事…")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .accessibilityLabel("备忘录内容")
            }
            .font(.body)
            .padding(.horizontal, 13)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Text("Esc 取消")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: save) {
                    HStack(spacing: 8) {
                        Text("保存")
                        Text("⌘↩")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(trimmedText.isEmpty || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.035))
        }
        .frame(width: 400, height: 270)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(model.colorSchemeMode.swiftUIColorScheme)
        .tint(ColorTokens.accent)
        .defaultFocus($isFocused, true)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(KeyEquivalent.escape) {
            onDismiss()
            return KeyPress.Result.handled
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedText.isEmpty, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let result = await model.addMemo(text)
            isSaving = false
            if result.shouldDismissEditor {
                text = ""
                onDismiss()
            }
        }
    }
}

private struct QuickMemoTitleStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(ColorTokens.accent)
            configuration.title
        }
    }
}
