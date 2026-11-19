import DailyCore
import SwiftUI

enum MemoPreviewMode: String, CaseIterable, Identifiable {
    case live
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "实时预览"
        case .source: "源码"
        }
    }
}

struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    let memo: Memo?
    private let isNew: Bool

    @State private var bodyText: String
    @State private var previewMode: MemoPreviewMode = .live
    @State private var isSaving = false

    init(model: AppModel, memo: Memo?) {
        self.model = model
        self.memo = memo
        self.isNew = memo == nil
        _bodyText = State(initialValue: memo?.body ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(isNew ? "新建备忘录" : "编辑备忘录")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("模式", selection: $previewMode) {
                    ForEach(MemoPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .labelsHidden()
            }
            .padding(20)

            Divider()

            editorBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
            }
            .padding(20)
        }
        .frame(width: 660, height: 500)
    }

    @ViewBuilder
    private var editorBody: some View {
        switch previewMode {
        case .live:
            MemoLivePreviewWebView(text: bodyText) { updated in
                bodyText = updated
            }
        case .source:
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .scrollContentBackground(.hidden)
        }
    }

    private var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        model.clearError()
        Task { @MainActor in
            let result: MutationResult
            if let memo {
                result = await model.updateMemo(id: memo.id, body: bodyText)
            } else {
                result = await model.addMemo(bodyText)
            }
            isSaving = false
            if result.shouldDismissEditor {
                dismiss()
            }
        }
    }
}
