import AppKit
import DailyCore
import SwiftUI

@MainActor
struct MenuBarActions {
    let model: AppModel

    func quickAdd(title: String) async -> MutationResult {
        await model.add(TaskDraft(title: title))
    }
}

struct MenuBarStatusLabel: View {
    @Bindable var model: AppModel

    var body: some View {
        Label(
            "Daily \(model.completedCount)/\(model.todayTasks.count)",
            systemImage: "checklist"
        )
        .accessibilityLabel(
            "Daily，已完成 \(model.completedCount) 项，共 \(model.todayTasks.count) 项"
        )
    }
}

struct MenuBarContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppModel

    @State private var completionPresentation = CompletionPresentationState()
    @State private var quickAddTitle = ""
    @State private var isAdding = false

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 14) {
            progressHeader

            if model.todayTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 8) {
                        LazyVStack(spacing: 8) {
                            ForEach(model.todayTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 330)
            }

            quickAdd

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("错误：\(errorMessage)")
            }

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开 Daily", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .frame(height: 38)
            .glassModule(interactive: true, cornerRadius: 13)
            .accessibilityHint("打开并置前主窗口")
        }
        .padding(14)
        .frame(width: 360)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日")
                    .font(.title2.weight(.bold))
                Spacer()
                Text("\(effectiveCompletedCount) / \(model.todayTasks.count)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Color.primary.opacity(0.78))
                        .frame(width: proxy.size.width * effectiveCompletionFraction)
                }
            }
            .frame(height: 6)
            .animation(motion.animation, value: effectiveCompletionFraction)
            .accessibilityElement()
            .accessibilityLabel("今日进度")
            .accessibilityValue("百分之 \(Int(effectiveCompletionFraction * 100))")
        }
        .padding(14)
        .glassModule(interactive: false, cornerRadius: 16)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 25, weight: .light))
            Text("今天还没有任务")
                .font(.headline)
            Text("在下方快速添加第一项。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassModule(interactive: false, cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private func taskRow(_ task: DailyTask) -> some View {
        let completed = effectiveCompletion(task)
        return Button {
            toggle(task)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))

                Text(task.titleSnapshot)
                    .font(.body.weight(.medium))
                    .strikethrough(completed)
                    .foregroundStyle(completed ? .secondary : .primary)
                    .lineLimit(2)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
        }
        .buttonStyle(.plain)
        .glassModule(interactive: true, cornerRadius: 14)
        .accessibilityLabel(task.titleSnapshot)
        .accessibilityValue(completed ? "已完成" : "未完成")
        .accessibilityHint(completed ? "取消完成" : "标记完成")
    }

    private var quickAdd: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("添加今日任务", text: $quickAddTitle)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
                .accessibilityLabel("菜单栏新任务标题")
            Button("添加", action: addTask)
                .buttonStyle(.borderless)
                .disabled(trimmedQuickAddTitle.isEmpty || isAdding)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .glassModule(interactive: true, cornerRadius: 14)
    }

    private var trimmedQuickAddTitle: String {
        quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveCompletedCount: Int {
        model.todayTasks.reduce(into: 0) { count, task in
            if effectiveCompletion(task) {
                count += 1
            }
        }
    }

    private var effectiveCompletionFraction: Double {
        guard !model.todayTasks.isEmpty else { return 0 }
        return Double(effectiveCompletedCount) / Double(model.todayTasks.count)
    }

    private func effectiveCompletion(_ task: DailyTask) -> Bool {
        completionPresentation.targetCompletion(taskID: task.id)
            ?? (task.completedAt != nil)
    }

    private func toggle(_ task: DailyTask) {
        let command = model.enqueueCompletion(
            task,
            completed: !effectiveCompletion(task)
        )
        withAnimation(motion.animation) {
            completionPresentation.submit(command)
        }
        Task { @MainActor in
            let token = await command.value
            withAnimation(motion.animation) {
                _ = completionPresentation.complete(command, token: token)
            }
        }
    }

    private func addTask() {
        let title = trimmedQuickAddTitle
        guard !title.isEmpty, !isAdding else { return }
        isAdding = true
        model.clearError()
        Task { @MainActor in
            let result = await MenuBarActions(model: model).quickAdd(title: title)
            isAdding = false
            if result.shouldDismissEditor {
                quickAddTitle = ""
            }
        }
    }
}
