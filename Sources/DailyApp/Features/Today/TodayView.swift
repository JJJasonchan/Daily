import DailyCore
import SwiftUI

struct PendingCompletionPresentation: Equatable, Sendable {
    let commandID: UUID
    let targetCompletion: Bool
}

struct CompletionPresentationState: Equatable, Sendable {
    private var pendingByTaskID: [UUID: PendingCompletionPresentation] = [:]
    private var latestSubmittedCommandID: UUID?
    private(set) var undoToken: CompletionUndoToken?

    mutating func submit(_ command: CompletionCommand) {
        latestSubmittedCommandID = command.id
        pendingByTaskID[command.taskID] = PendingCompletionPresentation(
            commandID: command.id,
            targetCompletion: command.targetCompletion
        )
    }

    func pending(taskID: UUID) -> PendingCompletionPresentation? {
        pendingByTaskID[taskID]
    }

    func targetCompletion(taskID: UUID) -> Bool? {
        pendingByTaskID[taskID]?.targetCompletion
    }

    @discardableResult
    mutating func complete(
        _ command: CompletionCommand,
        token: CompletionUndoToken?
    ) -> Bool {
        guard pendingByTaskID[command.taskID]?.commandID == command.id else {
            return false
        }
        pendingByTaskID[command.taskID] = nil
        guard latestSubmittedCommandID == command.id else {
            return false
        }
        if let token, token.sourceCommandID == command.id {
            undoToken = token
        }
        return true
    }

    mutating func dismissUndo(_ token: CompletionUndoToken) -> Bool {
        guard undoToken == token else { return false }
        undoToken = nil
        return true
    }

    @MainActor
    func visibleUndoToken(using model: AppModel) -> CompletionUndoToken? {
        guard let undoToken, model.isUndoAvailable(undoToken) else { return nil }
        return undoToken
    }
}

struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel

    @State private var completionPresentation = CompletionPresentationState()
    @State private var undoDismissalTask: Task<Void, Never>?
    @State private var pendingFutureDeletion: DailyTask?
    @State private var pendingSwipeDeletion: DailyTask?
    @State private var pendingUpcomingCancellation: DailyTask?
    @State private var quickAddText = ""
    @State private var isQuickAdding = false
    @FocusState private var isQuickAddFocused: Bool
    @State private var isInlineAdding = false
    @State private var inlineAddText = ""
    @State private var showCompleted = false
    @FocusState private var isInlineAddFocused: Bool

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if model.todayTasks.isEmpty {
                        emptyState
                    } else {
                        if !incompleteTasks.isEmpty {
                            ReorderableTaskList(
                                model: model,
                                isCompleted: effectiveCompletion,
                                onToggle: toggle,
                                onEdit: edit,
                                onDelete: requestDelete,
                                onSwipeDelete: swipeDelete
                            )
                            .padding(10)
                            .glassModule(interactive: false, cornerRadius: 18)

                            // Inline quick-add row
                            inlineQuickAddRow
                        }

                        // Completed section
                        if !completedTasks.isEmpty {
                            completedSection
                        }
                    }
                    if !model.upcomingTasks.isEmpty {
                        upcomingSection
                    }
                }
                .fluidRowHighlightScope(cornerRadius: TaskRow.cornerRadius)
                .frame(maxWidth: 760)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
            }

            if let undoToken = visibleUndoToken {
                undoOverlay(for: undoToken)
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text("📝")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("新任务（回车添加）", text: $quickAddText)
                        .textFieldStyle(.plain)
                        .onSubmit(submitQuickAdd)
                        .accessibilityLabel("新任务标题")

                    Button {
                        model.isPresentingNewTask = true
                    } label: {
                        Image(systemName: "plus.square.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("打开完整任务编辑器（可设置重复、提醒、计划日期）")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .frame(minWidth: 360, idealWidth: 500)
                .glassModule(interactive: true, cornerRadius: 10)
            }
        }
        .onDisappear {
            undoDismissalTask?.cancel()
        }
        .confirmationDialog(
            "停止以后重复？",
            isPresented: futureDeletePresentation,
            titleVisibility: .visible
        ) {
            Button("停止以后重复", role: .destructive) {
                guard let task = pendingFutureDeletion else { return }
                pendingFutureDeletion = nil
                Task { @MainActor in
                    await model.delete(task, scope: .allFuture)
                }
            }
            Button("取消", role: .cancel) {
                pendingFutureDeletion = nil
            }
        } message: {
            Text("今天的任务将被移除，此规则以后不再生成任务；历史记录不会改变。")
        }
        .confirmationDialog(
            "删除“\(swipeDeletionTitle)”？",
            isPresented: swipeDeletionPresentation,
            titleVisibility: .visible
        ) {
            Button("仅删除今天", role: .destructive) {
                guard let task = pendingSwipeDeletion else { return }
                pendingSwipeDeletion = nil
                Task { @MainActor in
                    await model.delete(task, scope: .todayOnly)
                }
            }
            Button("删除整个重复任务", role: .destructive) {
                guard let task = pendingSwipeDeletion else { return }
                pendingSwipeDeletion = nil
                Task { @MainActor in
                    await model.delete(task, scope: .allFuture)
                }
            }
            Button("取消", role: .cancel) {
                pendingSwipeDeletion = nil
            }
        } message: {
            Text("删除整个重复任务会停止以后的生成，历史记录不会改变。")
        }
    }

    private var upcomingSection: some View {
        let tasksByDay = Dictionary(grouping: model.upcomingTasks, by: \.dayKey)

        return VStack(alignment: .leading, spacing: 12) {
            Text("即将到来")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(tasksByDay.keys.sorted(), id: \.self) { dayKey in
                let date = LocalDay(rawValue: dayKey).date(in: .autoupdatingCurrent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.year().month().day().weekday()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(tasksByDay[dayKey] ?? [], id: \.id) { task in
                        HStack(spacing: 12) {
                            Button {
                                edit(task)
                            } label: {
                                Text(task.titleSnapshot)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help("编辑或改期")

                            Menu {
                                Button("编辑或改期") { edit(task) }
                                Button("取消安排", role: .destructive) {
                                    pendingUpcomingCancellation = task
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel("管理 \(task.titleSnapshot)")
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassModule(interactive: false, cornerRadius: 18)
        .confirmationDialog(
            "取消这项安排？",
            isPresented: Binding(
                get: { pendingUpcomingCancellation != nil },
                set: { if !$0 { pendingUpcomingCancellation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUpcomingCancellation
        ) { task in
            Button("取消安排", role: .destructive) {
                Task { @MainActor in await model.cancelUpcoming(task) }
            }
        } message: { task in
            Text(task.titleSnapshot)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            dateBlock

            Spacer(minLength: 8)

            TodayCompletionRing(
                progress: todayCompletionProgress,
                motion: motion
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassModule(interactive: false, cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            ColorTokens.accent.opacity(0.25),
                            ColorTokens.accent.opacity(0.0)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
        }
        .padding(.bottom, 4)
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(weekdayText.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 10) {
                Text(dayNumberText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(monthText)
                        .font(.title3.weight(.semibold))
                    Text(greeting)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(timeEmoji)
                .font(.system(size: 40))

            Text(emptyGreeting)
                .font(.title3.weight(.semibold))

            Text("在下方面板快速添加，或打开编辑器设置重复与提醒。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                EmptyQuickSuggestion(
                    emoji: "✏️",
                    text: "写下第一个任务",
                    action: { model.isPresentingNewTask = true }
                )
                EmptyQuickSuggestion(
                    emoji: "⏰",
                    text: "设置每日提醒",
                    action: { model.destination = .settings }
                )
                EmptyQuickSuggestion(
                    emoji: "📋",
                    text: "查看历史记录",
                    action: { model.destination = .history }
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .glassModule(interactive: false, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var timeEmoji: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "☀️"
        case 12..<14: return "🌤"
        case 14..<18: return "🌅"
        default: return "🌙"
        }
    }

    private var emptyGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "早上好！今天还没有任务"
        case 12..<14: return "中午好！休息一下再开始"
        case 14..<18: return "下午好！今天还没有任务"
        default: return "晚上好！今天还没有任务"
        }
    }

    private func undoOverlay(for token: CompletionUndoToken) -> some View {
        HStack(spacing: 12) {
            Text("任务状态已更新")
                .font(.subheadline.weight(.medium))
            Button("撤销") {
                undo(token)
            }
                .buttonStyle(.borderless)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassModule(interactive: true, cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("任务状态已更新，可撤销")
    }

    private var effectiveCompletedCount: Int {
        model.todayTasks.reduce(into: 0) { count, task in
            if effectiveCompletion(task) {
                count += 1
            }
        }
    }

    private var visibleUndoToken: CompletionUndoToken? {
        completionPresentation.visibleUndoToken(using: model)
    }

    private var todayCompletionProgress: TodayCompletionProgress {
        TodayCompletionProgress(
            completed: effectiveCompletedCount,
            total: model.todayTasks.count
        )
    }

    private var weekdayText: String {
        Date.now.formatted(.dateTime.weekday(.wide))
    }

    private var dayNumberText: String {
        Date.now.formatted(.dateTime.day())
    }

    private var monthText: String {
        Date.now.formatted(.dateTime.month(.wide))
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "☀️ 早上好"
        case 12..<14: "🌤 中午好"
        case 14..<18: "🌅 下午好"
        default: "🌙 晚上好"
        }
    }

    private func effectiveCompletion(_ task: DailyTask) -> Bool {
        model.pendingCompletionTarget(taskID: task.id)
            ?? completionPresentation.targetCompletion(taskID: task.id)
            ?? (task.completedAt != nil)
    }

    private func toggle(_ task: DailyTask) {
        let targetCompletion = !effectiveCompletion(task)
        let animation = motion.animation

        let command = model.enqueueCompletion(task, completed: targetCompletion)
        withAnimation(animation) {
            completionPresentation.submit(command)
        }
        Task { @MainActor in
            let token = await command.value
            let didPublishToken: Bool = withAnimation(animation) {
                completionPresentation.complete(command, token: token)
            }
            if let token, didPublishToken,
               completionPresentation.undoToken == token {
                scheduleUndoDismissal(for: token)
            }
        }
    }

    private func edit(_ task: DailyTask) {
        model.editorTaskID = task.id
    }

    private func requestDelete(_ task: DailyTask, scope: DeleteScope) {
        switch scope {
        case .todayOnly:
            Task { @MainActor in
                await model.delete(task, scope: .todayOnly)
            }
        case .allFuture:
            pendingFutureDeletion = task
        }
    }

    private func swipeDelete(_ task: DailyTask) async {
        let isRecurring = model.templates.first { $0.id == task.templateID }?.kind == .recurring
        if isRecurring {
            pendingSwipeDeletion = task
        } else {
            await model.delete(task, scope: .todayOnly)
        }
    }

    private func submitQuickAdd() {
        let text = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isQuickAdding else { return }
        isQuickAdding = true
        model.clearError()
        Task { @MainActor in
            let result = await model.add(TaskDraft(title: text))
            isQuickAdding = false
            if result.shouldDismissEditor {
                quickAddText = ""
                isQuickAddFocused = true
            }
        }
    }

    private var futureDeletePresentation: Binding<Bool> {
        Binding(
            get: { pendingFutureDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingFutureDeletion = nil
                }
            }
        )
    }

    private var swipeDeletionPresentation: Binding<Bool> {
        Binding(
            get: { pendingSwipeDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSwipeDeletion = nil
                }
            }
        )
    }

    private var swipeDeletionTitle: String {
        pendingSwipeDeletion?.titleSnapshot ?? "任务"
    }

    private func scheduleUndoDismissal(for token: CompletionUndoToken) {
        undoDismissalTask?.cancel()
        undoDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  model.isUndoAvailable(token),
                  visibleUndoToken == token else { return }
            withAnimation(motion.animation) {
                _ = completionPresentation.dismissUndo(token)
            }
        }
    }

    // MARK: - Task grouping

    private var incompleteTasks: [DailyTask] {
        model.todayTasks.filter { !effectiveCompletion($0) }
    }

    private var completedTasks: [DailyTask] {
        model.todayTasks.filter { effectiveCompletion($0) }
    }

    // MARK: - Inline quick add

    private var inlineQuickAddRow: some View {
        VStack(spacing: 0) {
            if isInlineAdding {
                HStack(spacing: 10) {
                    TextField("输入任务标题", text: $inlineAddText)
                        .textFieldStyle(.plain)
                        .focused($isInlineAddFocused)
                        .onSubmit(submitInlineAdd)
                        .accessibilityLabel("新任务标题")

                    Button("添加") {
                        submitInlineAdd()
                    }
                    .buttonStyle(.borderless)
                    .disabled(inlineAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        isInlineAdding = false
                        inlineAddText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .glassModule(interactive: true, cornerRadius: 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button {
                    startInlineAdd()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("添加任务")
                            .font(.body)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .animation(motion.animation, value: isInlineAdding)
    }

    private func startInlineAdd() {
        isInlineAdding = true
        inlineAddText = ""
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isInlineAddFocused = true
        }
    }

    private func submitInlineAdd() {
        let text = inlineAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isQuickAdding else { return }
        isQuickAdding = true
        model.clearError()
        Task { @MainActor in
            let result = await model.add(TaskDraft(title: text))
            isQuickAdding = false
            if result.shouldDismissEditor {
                inlineAddText = ""
                isInlineAddFocused = true
            }
        }
    }

    // MARK: - Completed section

    private var completedSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(motion.animation) {
                    showCompleted.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("✓ 已完成")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("(\(completedTasks.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showCompleted ? "收起已完成任务" : "展开已完成任务")

            if showCompleted {
                VStack(spacing: 8) {
                    ForEach(completedTasks, id: \.id) { task in
                        completedTaskRow(task)
                    }
                }
                .padding(10)
                .glassModule(interactive: false, cornerRadius: 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func isTaskRecurring(_ task: DailyTask) -> Bool {
        (model.templates.first { $0.id == task.templateID }?.kind == .recurring)
    }

    @ViewBuilder
    private func completedTaskRow(_ task: DailyTask) -> some View {
        TaskRow(
            task: task,
            isCompleted: true,
            isRecurring: isTaskRecurring(task),
            isDragSource: false,
            onToggle: { toggle(task) },
            onEdit: { edit(task) },
            onDelete: { scope in requestDelete(task, scope: scope) }
        )
    }

    private func undo(_ token: CompletionUndoToken) {
        guard model.isUndoAvailable(token), visibleUndoToken == token else { return }
        withAnimation(motion.animation) {
            _ = completionPresentation.dismissUndo(token)
        }
        _ = model.enqueueUndo(token)
    }
}

// MARK: - Empty state helpers

private struct EmptyQuickSuggestion: View {
    let emoji: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 16))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(ColorTokens.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) \(text)")
        .accessibilityHint("点击添加")
    }
}
