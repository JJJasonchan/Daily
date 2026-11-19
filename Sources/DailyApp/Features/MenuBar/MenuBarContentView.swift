import AppKit
import DailyCore
import SwiftUI

@MainActor
struct MenuBarActions {
    let model: AppModel

    func quickAdd(title: String) async -> MutationResult {
        await model.add(TaskDraft(title: title))
    }

    func undo(_ token: CompletionUndoToken) async {
        await model.undo(token)
    }
}

enum MenuBarListProjection {
    /// 单行最小高度，与 taskRow 的 frame(minHeight:) 保持一致。
    static let rowMinHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 8
    static let listVerticalPadding: CGFloat = 10
    /// 列表最大高度；超出后改为滚动，避免面板长过屏幕。
    static let maxListHeight: CGFloat = 330

    static func remainingTasks(
        in tasks: [DailyTask],
        isCompleted: (DailyTask) -> Bool
    ) -> [DailyTask] {
        tasks.filter { !isCompleted($0) }
    }

    /// MenuBarExtra(.window) 会把窗口高度贴合内容，而 ScrollView 没有固有高度：
    /// 不给确定高度时整块列表会被压成 0，看起来就像"任务不见了"。
    static func listHeight(forRowCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = CGFloat(count) * rowMinHeight
        let gaps = CGFloat(count - 1) * rowSpacing
        return min(rows + gaps + listVerticalPadding * 2, maxListHeight)
    }

    static func isScrollable(forRowCount count: Int) -> Bool {
        count > 0 && listHeight(forRowCount: count) >= maxListHeight
    }
}

enum MenuBarStatusProjection {
    /// pendingTarget 用于乐观更新：点击勾选后立刻反映，不等落库。
    static func completedCount(
        in tasks: [DailyTask],
        pendingTarget: (UUID) -> Bool? = { _ in nil }
    ) -> Int {
        var count = 0
        for task in tasks {
            if pendingTarget(task.id) ?? (task.completedAt != nil) {
                count += 1
            }
        }
        return count
    }

    /// 状态栏只显示图标，不显示任何数字或文字。
    static func systemImage(completed: Int, total: Int) -> String {
        guard total > 0, completed >= total else { return "checklist" }
        return "checkmark.circle.fill"
    }

    static func accessibilityLabel(completed: Int, total: Int) -> String {
        guard total > 0 else { return "Daily，今天还没有任务" }
        return "Daily，已完成 \(completed) 项，共 \(total) 项"
    }
}

struct MenuBarStatusLabel: View {
    @Bindable var model: AppModel

    private var total: Int { model.todayTasks.count }
    private var completed: Int {
        MenuBarStatusProjection.completedCount(
            in: model.todayTasks,
            pendingTarget: { model.pendingCompletionTarget(taskID: $0) }
        )
    }

    var body: some View {
        Image(systemName: MenuBarStatusProjection.systemImage(completed: completed, total: total))
            .accessibilityLabel(
                MenuBarStatusProjection.accessibilityLabel(completed: completed, total: total)
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
    @State private var isUndoing = false
    @State private var showCompleted = false
    @State private var undoDismissalTask: Task<Void, Never>?

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 14) {
            progressHeader

            if model.todayTasks.isEmpty {
                emptyState
            } else if remainingTasks.isEmpty {
                allDoneState
                if !completedTasks.isEmpty {
                    completedSection
                }
            } else {
                remainingList

                if !completedTasks.isEmpty {
                    completedSection
                }
            }

            quickAdd

            if let undoToken = visibleUndoToken {
                undoBar(for: undoToken)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("错误：\(errorMessage)")
            }

            Button {
                showQuickMemoWindow()
            } label: {
                Label("记录备忘录", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .frame(height: 38)
            .glassModule(interactive: true, cornerRadius: 13)
            .accessibilityHint("打开快速备忘录")

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

        .preferredColorScheme(model.colorSchemeMode.swiftUIColorScheme)
        .tint(ColorTokens.accent)
        .padding(14)
        .frame(width: 360)
        .onDisappear {
            undoDismissalTask?.cancel()
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("✅ 今日")
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

    private var allDoneState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(ColorTokens.accent)
            Text("今天全部完成")
                .font(.headline)
            Text("干得漂亮！")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassModule(interactive: false, cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var remainingTasks: [DailyTask] {
        MenuBarListProjection.remainingTasks(
            in: model.todayTasks,
            isCompleted: { effectiveCompletion($0) }
        )
    }

    private var completedTasks: [DailyTask] {
        model.todayTasks.filter { effectiveCompletion($0) }
    }

    /// 未完成列表。高度必须显式给定：MenuBarExtra(.window) 会贴合内容，
    /// 而 ScrollView 没有固有高度，只写 maxHeight 会被压成 0 条。
    private var remainingList: some View {
        let height = MenuBarListProjection.listHeight(forRowCount: remainingTasks.count)
        return ScrollView {
            LazyVStack(spacing: MenuBarListProjection.rowSpacing) {
                ForEach(remainingTasks) { task in
                    taskRow(task)
                }
            }
            .padding(MenuBarListProjection.listVerticalPadding)
            .glassModule(interactive: false, cornerRadius: 18)
        }
        .scrollDisabled(!MenuBarListProjection.isScrollable(forRowCount: remainingTasks.count))
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("未完成任务，共 \(remainingTasks.count) 项")
    }

    private var completedSection: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(motion.animation) {
                    showCompleted.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("已完成 \(completedTasks.count)")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("已完成 \(completedTasks.count) 项")
            .accessibilityHint(showCompleted ? "收起已完成任务" : "展开已完成任务")

            if showCompleted {
                ScrollView {
                    LazyVStack(spacing: MenuBarListProjection.rowSpacing) {
                        ForEach(completedTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(MenuBarListProjection.listVerticalPadding)
                    .glassModule(interactive: false, cornerRadius: 16)
                }
                .frame(
                    height: min(
                        MenuBarListProjection.listHeight(forRowCount: completedTasks.count),
                        MenuBarListProjection.maxListHeight
                    )
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private func taskRow(_ task: DailyTask) -> some View {
        let completed = effectiveCompletion(task)
        return Button {
            toggle(task)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(completed ? ColorTokens.checkboxComplete : ColorTokens.checkboxIncomplete)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: completed)

                Text(task.titleSnapshot)
                    .font(.body.weight(.medium))
                    .strikethrough(completed)
                    .foregroundStyle(completed ? .secondary : .primary)
                    .lineLimit(2)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 13)
            .frame(minHeight: MenuBarListProjection.rowMinHeight)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(completed ? 0.03 : 0.0))
        }
        .opacity(completed ? 0.72 : 1)
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

    private var visibleUndoToken: CompletionUndoToken? {
        completionPresentation.visibleUndoToken(using: model)
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
        model.pendingCompletionTarget(taskID: task.id)
            ?? completionPresentation.targetCompletion(taskID: task.id)
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
            let didPublishToken: Bool = withAnimation(motion.animation) {
                completionPresentation.complete(command, token: token)
            }
            if let token, didPublishToken,
               completionPresentation.undoToken == token {
                scheduleUndoDismissal(for: token)
            }
        }
    }

    private func undoBar(for token: CompletionUndoToken) -> some View {
        HStack(spacing: 10) {
            Text("任务状态已更新")
                .font(.subheadline.weight(.medium))
            Spacer()
            if isUndoing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在撤销")
            }
            Button("撤销") {
                undo(token)
            }
            .buttonStyle(.borderless)
            .disabled(isUndoing)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .glassModule(interactive: !isUndoing, cornerRadius: 13)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUndoing ? "正在撤销任务状态" : "任务状态已更新，可撤销")
    }

    private func scheduleUndoDismissal(for token: CompletionUndoToken) {
        undoDismissalTask?.cancel()
        undoDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  !isUndoing,
                  model.isUndoAvailable(token),
                  visibleUndoToken == token else { return }
            withAnimation(motion.animation) {
                _ = completionPresentation.dismissUndo(token)
            }
        }
    }

    private func undo(_ token: CompletionUndoToken) {
        guard !isUndoing,
              model.isUndoAvailable(token),
              visibleUndoToken == token else { return }
        undoDismissalTask?.cancel()
        isUndoing = true
        Task { @MainActor in
            await MenuBarActions(model: model).undo(token)
            isUndoing = false
            guard model.lastCompletionUndo != token else { return }
            withAnimation(motion.animation) {
                _ = completionPresentation.dismissUndo(token)
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
