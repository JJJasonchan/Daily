import DailyCore
import SwiftUI

struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel

    @State private var pendingCompletion: [UUID: Bool] = [:]
    @State private var showsUndo = false
    @State private var completionTask: Task<Void, Never>?
    @State private var undoDismissalTask: Task<Void, Never>?

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
                        GlassEffectContainer(spacing: ReorderableTaskList.rowSpacing) {
                            ReorderableTaskList(
                                model: model,
                                isCompleted: effectiveCompletion,
                                onToggle: toggle,
                                onEdit: edit
                            )
                        }
                    }

                    QuickAddView(model: model)
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
            }

            if showsUndo {
                undoOverlay
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem {
                Button {
                    model.isPresentingNewTask = true
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onDisappear {
            undoDismissalTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日")
                        .font(.largeTitle.weight(.bold))
                    Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(effectiveCompletedCount) / \(model.todayTasks.count)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "已完成 \(effectiveCompletedCount) 项，共 \(model.todayTasks.count) 项"
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Color.primary.opacity(0.78))
                        .frame(width: proxy.size.width * effectiveCompletionFraction)
                }
            }
            .frame(height: 7)
            .animation(motion.animation, value: effectiveCompletionFraction)
            .accessibilityElement()
            .accessibilityLabel("今日进度")
            .accessibilityValue("百分之 \(Int(effectiveCompletionFraction * 100))")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30, weight: .light))
            Text("今天还没有任务")
                .font(.headline)
            Text("在下方添加一项，或打开完整编辑器设置重复与提醒。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .glassModule(interactive: false, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var undoOverlay: some View {
        HStack(spacing: 12) {
            Text("任务状态已更新")
                .font(.subheadline.weight(.medium))
            Button("撤销", action: undo)
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

    private var effectiveCompletionFraction: Double {
        guard !model.todayTasks.isEmpty else { return 0 }
        return Double(effectiveCompletedCount) / Double(model.todayTasks.count)
    }

    private func effectiveCompletion(_ task: DailyTask) -> Bool {
        pendingCompletion[task.id] ?? (task.completedAt != nil)
    }

    private func toggle(_ task: DailyTask) {
        let targetCompletion = !effectiveCompletion(task)
        let animation = motion.animation

        withAnimation(animation) {
            pendingCompletion[task.id] = targetCompletion
            showsUndo = true
        }
        scheduleUndoDismissal()

        let precedingCompletionTask = completionTask
        completionTask = Task { @MainActor in
            await precedingCompletionTask?.value
            await model.toggle(task)
            withAnimation(animation) {
                pendingCompletion[task.id] = nil
            }
        }
    }

    private func edit(_ task: DailyTask) {
        model.editorTaskID = task.id
    }

    private func scheduleUndoDismissal() {
        undoDismissalTask?.cancel()
        undoDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(motion.animation) {
                showsUndo = false
            }
        }
    }

    private func undo() {
        undoDismissalTask?.cancel()
        let pendingCompletionTask = completionTask
        withAnimation(motion.animation) {
            showsUndo = false
            pendingCompletion.removeAll()
        }
        Task { @MainActor in
            await pendingCompletionTask?.value
            await model.undoLastCompletion()
        }
    }
}
