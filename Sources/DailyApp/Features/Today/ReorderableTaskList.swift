import DailyCore
import SwiftUI

enum ReorderLayout {
    static func destinationIndex(
        startIndex: Int,
        translation: CGFloat,
        rowStride: CGFloat,
        count: Int
    ) -> Int {
        guard count > 0, rowStride > 0 else { return 0 }
        let rawIndex = CGFloat(startIndex) + translation / rowStride
        let roundedIndex = Int((rawIndex + 0.5).rounded(.down))
        return min(max(roundedIndex, 0), count - 1)
    }

    static func neighborOffset(
        itemIndex: Int,
        startIndex: Int,
        translation: CGFloat,
        rowStride: CGFloat
    ) -> CGFloat {
        if translation > 0, itemIndex > startIndex {
            let delayedDistance = CGFloat(itemIndex - startIndex - 1) * rowStride
            return -min(max(translation - delayedDistance, 0), rowStride)
        }
        if translation < 0, itemIndex < startIndex {
            let delayedDistance = CGFloat(startIndex - itemIndex - 1) * rowStride
            return min(max(-translation - delayedDistance, 0), rowStride)
        }
        return 0
    }
}

struct ReorderableTaskList: View {
    static let rowHeight: CGFloat = 58
    static let rowSpacing: CGFloat = 8
    static let coordinateSpaceName = "daily-task-reorder-space"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel

    let isCompleted: (DailyTask) -> Bool
    let onToggle: (DailyTask) -> Void
    let onEdit: (DailyTask) -> Void
    let onDelete: (DailyTask, DeleteScope) -> Void

    @State private var dragSnapshot: [DailyTask]?
    @State private var activeTaskID: UUID?
    @State private var startIndex = 0
    @State private var lastDestination = 0
    @State private var grabOffset: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var settlingTask: Task<Void, Never>?

    private var rowStride: CGFloat {
        Self.rowHeight + Self.rowSpacing
    }

    private var visibleTasks: [DailyTask] {
        dragSnapshot ?? model.todayTasks
    }

    var body: some View {
        let tasks = visibleTasks

        ZStack(alignment: .topLeading) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    row(task, index: index)
                        .opacity(activeTaskID == task.id ? 0 : 1)
                        .offset(
                            y: activeTaskID == nil
                                ? 0
                                : ReorderLayout.neighborOffset(
                                    itemIndex: index,
                                    startIndex: startIndex,
                                    translation: dragTranslation,
                                    rowStride: rowStride
                                )
                        )
                }
            }

            if let activeTask {
                row(activeTask, index: startIndex, isDragSource: true)
                    .offset(y: CGFloat(startIndex) * rowStride + dragTranslation)
                    .zIndex(1)
            }
        }
        .frame(height: totalHeight(for: tasks.count), alignment: .top)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日任务列表")
    }

    @ViewBuilder
    private func row(
        _ task: DailyTask,
        index: Int,
        isDragSource: Bool = false
    ) -> some View {
        TaskRow(
            task: task,
            isCompleted: isCompleted(task),
            isRecurring: model.templates.first { $0.id == task.templateID }?.kind == .recurring,
            isDragSource: isDragSource,
            onToggle: { onToggle(task) },
            onEdit: { onEdit(task) },
            onDragChanged: { value in
                dragChanged(value, task: task, fallbackIndex: index)
            },
            onDragEnded: { value in
                dragEnded(value)
            },
            onDelete: { scope in onDelete(task, scope) }
        )
    }

    private var activeTask: DailyTask? {
        guard let activeTaskID else { return nil }
        return visibleTasks.first { $0.id == activeTaskID }
    }

    private func totalHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * Self.rowHeight
            + CGFloat(count - 1) * Self.rowSpacing
    }

    private func dragChanged(
        _ value: DragGesture.Value,
        task: DailyTask,
        fallbackIndex: Int
    ) {
        if settlingTask != nil {
            settlingTask?.cancel()
            resetDrag()
        }

        if activeTaskID == nil {
            beginDrag(value, task: task, fallbackIndex: fallbackIndex)
        }

        let sourceTop = CGFloat(startIndex) * rowStride
        dragTranslation = value.location.y - grabOffset - sourceTop
        reorderIfDestinationChanged(using: dragTranslation)
    }

    private func beginDrag(
        _ value: DragGesture.Value,
        task: DailyTask,
        fallbackIndex: Int
    ) {
        let snapshot = model.todayTasks
        let index = snapshot.firstIndex { $0.id == task.id } ?? fallbackIndex
        dragSnapshot = snapshot
        activeTaskID = task.id
        startIndex = index
        lastDestination = index
        grabOffset = value.startLocation.y - CGFloat(index) * rowStride
        dragTranslation = 0
    }

    private func dragEnded(_ value: DragGesture.Value) {
        guard activeTaskID != nil else { return }

        let projectedTranslation = reduceMotion
            ? dragTranslation
            : value.predictedEndTranslation.height
        reorderIfDestinationChanged(using: projectedTranslation)

        guard !reduceMotion else {
            resetDrag()
            return
        }

        let targetTranslation = CGFloat(lastDestination - startIndex) * rowStride
        let motion = MotionTokens.physical
        withAnimation(motion.animation) {
            dragTranslation = targetTranslation
        }

        settlingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(motion.duration))
            guard !Task.isCancelled else { return }
            resetDrag()
        }
    }

    private func reorderIfDestinationChanged(using translation: CGFloat) {
        guard let snapshot = dragSnapshot else { return }
        let destination = ReorderLayout.destinationIndex(
            startIndex: startIndex,
            translation: translation,
            rowStride: rowStride,
            count: snapshot.count
        )
        guard destination != lastDestination else { return }

        lastDestination = destination
        var ids = snapshot.map(\.id)
        let activeID = ids.remove(at: startIndex)
        ids.insert(activeID, at: destination)
        model.reorder(ids: ids)
    }

    private func resetDrag() {
        settlingTask?.cancel()
        settlingTask = nil
        dragSnapshot = nil
        activeTaskID = nil
        startIndex = 0
        lastDestination = 0
        grabOffset = 0
        dragTranslation = 0
    }
}
