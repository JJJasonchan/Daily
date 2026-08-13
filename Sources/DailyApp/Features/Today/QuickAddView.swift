import DailyCore
import SwiftUI

struct QuickAddView: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool
    @State private var title = ""
    @State private var isSaving = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)

            TextField("添加今日任务", text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(addTask)
                .accessibilityLabel("新任务标题")

            Button("添加", action: addTask)
                .buttonStyle(.borderless)
                .disabled(trimmedTitle.isEmpty || isSaving)

            Divider()
                .frame(height: 18)

            Button {
                model.isPresentingNewTask = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("打开完整任务编辑器")
            .accessibilityLabel("打开完整任务编辑器")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassModule(interactive: true, cornerRadius: 15)
        .task(id: model.quickAddFocusRequestID) {
            guard model.quickAddFocusRequestID != nil else { return }
            await Task.yield()
            isFocused = true
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTask() {
        let submittedTitle = trimmedTitle
        guard !submittedTitle.isEmpty, !isSaving else { return }

        isSaving = true
        model.clearError()
        Task { @MainActor in
            let result = await model.add(TaskDraft(title: submittedTitle))
            isSaving = false
            if result.shouldDismissEditor {
                title = ""
                isFocused = true
            }
        }
    }
}
