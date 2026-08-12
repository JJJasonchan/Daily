import DailyCore
import SwiftUI

/// 拖拽重排的核心实现。关键设计：
/// 1. dragStartIndex 在拖拽期间永不变 — 拖动行始终从原始位置出发
/// 2. 拖拽中只操作本地 snapshot，不调用 model.reorder()
/// 3. 松手时才写入最终顺序
/// 4. 邻居行使用 spring 动画平滑让位
struct ReorderableTaskList: View {
    static let rowHeight: CGFloat = 58
    static let rowSpacing: CGFloat = 8
    static let rowStride: CGFloat = rowHeight + rowSpacing
    static let swipeDeleteThreshold: CGFloat = 68
    static let swipeDirectionThreshold: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel

    let isCompleted: (DailyTask) -> Bool
    let onToggle: (DailyTask) -> Void
    let onEdit: (DailyTask) -> Void
    let onDelete: (DailyTask, DeleteScope) -> Void
    let onSwipeDelete: (DailyTask) -> Void

    // 拖拽状态机
    enum DragState: Equatable {
        case idle
        case dragging(snapshot: [DailyTask], activeID: UUID, startIndex: Int)
        case settling(snapshot: [DailyTask], activeID: UUID, startIndex: Int, targetIndex: Int)
    }

    @State private var dragState: DragState = .idle
    @State private var dragTranslation: CGFloat = 0
    @State private var settlingWorkItem: DispatchWorkItem?
    @State private var swipeTaskID: UUID?
    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        let tasks = visibleTasks
        let activeID = activeTaskID
        let startIndex = dragStartIndex

        ZStack(alignment: .topLeading) {
            // 底层：所有任务行（被拖的行透明度=0）
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    taskRow(task, isDragging: activeID == task.id)
                        .opacity(activeID == task.id ? 0 : 1)
                        .offset(y: neighborYOffset(index: index))
                }
            }
            .animation(.interpolatingSpring(duration: 0.30, bounce: 0.12), value: dragTranslation)

            // 顶层：浮起的拖拽行
            if let activeID, let activeTask = tasks.first(where: { $0.id == activeID }) {
                taskRow(activeTask, isDragging: true)
                    .offset(y: CGFloat(startIndex) * Self.rowStride + dragTranslation)
                    .zIndex(10)
                    .shadow(color: .primary.opacity(0.22), radius: 16, y: 8)
            }
        }
        .frame(height: totalHeight(for: tasks.count), alignment: .top)
    }

    // MARK: - 邻居行偏移

    private func neighborYOffset(index: Int) -> CGFloat {
        let startIdx: Int
        switch dragState {
        case .idle:
            return 0
        case .dragging(_, _, let s):
            startIdx = s
        case .settling(_, _, let s, _):
            startIdx = s
        }
        return ReorderLayout.neighborOffset(
            itemIndex: index,
            startIndex: startIdx,
            translation: dragTranslation,
            rowStride: Self.rowStride
        )
    }

    // MARK: - 信息

    private var visibleTasks: [DailyTask] {
        switch dragState {
        case .idle:
            return model.todayTasks
        case .dragging(let snap, _, _), .settling(let snap, _, _, _):
            return snap
        }
    }

    private var activeTaskID: UUID? {
        switch dragState {
        case .idle: return nil
        case .dragging(_, let id, _), .settling(_, let id, _, _): return id
        }
    }

    private var dragStartIndex: Int {
        switch dragState {
        case .idle: return 0
        case .dragging(_, _, let idx), .settling(_, _, let idx, _): return idx
        }
    }

    // MARK: - Row

    private func taskRow(_ task: DailyTask, isDragging: Bool) -> some View {
        ZStack(alignment: .trailing) {
            swipeDeleteBackground(for: task)

            TaskRow(
                task: task,
                isCompleted: isCompleted(task),
                isRecurring: model.templates.first { $0.id == task.templateID }?.kind == .recurring,
                isDragSource: isDragging,
                onToggle: { onToggle(task) },
                onEdit: { onEdit(task) },
                onDelete: { scope in onDelete(task, scope) }
            )
            .offset(x: swipeTaskID == task.id ? swipeOffset : 0)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in handleRowDragChanged(value, task: task) }
                    .onEnded { value in handleRowDragEnded(value, task: task) }
            )
        }
    }

    // MARK: - 侧拉删除

    private func swipeDeleteBackground(for task: DailyTask) -> some View {
        let isRevealed = swipeTaskID == task.id && swipeOffset < 0
        return Button {
            resetSwipe()
            onSwipeDelete(task)
        } label: {
            Image(systemName: "trash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.rowHeight)
                .frame(maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.red.gradient)
                }
        }
        .buttonStyle(.plain)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .accessibilityLabel("删除 \(task.titleSnapshot)")
    }

    private func clampedSwipeOffset(_ x: CGFloat) -> CGFloat {
        guard x < 0 else { return 0 }
        let overshoot = -x - Self.swipeDeleteThreshold
        guard overshoot > 0 else { return x }
        return -(Self.swipeDeleteThreshold + overshoot * 0.3)
    }

    private func resetSwipe() {
        swipeTaskID = nil
        if reduceMotion {
            swipeOffset = 0
        } else {
            withAnimation(.spring(duration: 0.38, bounce: 0.10)) {
                swipeOffset = 0
            }
        }
    }

    // MARK: - 手势处理

    private func handleRowDragChanged(_ value: DragGesture.Value, task: DailyTask) {
        settlingWorkItem?.cancel()
        settlingWorkItem = nil

        if let swipeID = swipeTaskID {
            guard swipeID == task.id else { return }
            swipeOffset = clampedSwipeOffset(value.translation.width)
            return
        }

        switch dragState {
        case .idle:
            let dx = value.translation.width
            let dy = value.translation.height
            if dx < -Self.swipeDirectionThreshold, abs(dx) > abs(dy) {
                swipeTaskID = task.id
                swipeOffset = clampedSwipeOffset(dx)
                return
            }
            let snapshot = model.todayTasks
            guard let idx = snapshot.firstIndex(where: { $0.id == task.id }) else { return }
            dragState = .dragging(snapshot: snapshot, activeID: task.id, startIndex: idx)
            dragTranslation = 0
        case .settling:
            // 手势被打断，从上一次 settle 位置继续
            if case .settling(let snap, let id, let startIdx, _) = dragState {
                dragState = .dragging(snapshot: snap, activeID: id, startIndex: startIdx)
            }
        case .dragging:
            break
        }

        // 1:1 跟随手指
        dragTranslation = value.translation.height
        reorderInSnapshot()
    }

    private func handleRowDragEnded(_ value: DragGesture.Value, task: DailyTask) {
        if let swipeID = swipeTaskID, swipeID == task.id {
            let shouldDelete = swipeOffset <= -Self.swipeDeleteThreshold
            resetSwipe()
            if shouldDelete {
                onSwipeDelete(task)
            }
            return
        }

        guard case .dragging(let snapshot, let activeID, let startIdx) = dragState else { return }

        let predicted = reduceMotion ? dragTranslation : value.predictedEndTranslation.height
        dragTranslation = predicted

        // 计算最终目标位置
        let targetIdx = ReorderLayout.destinationIndex(
            startIndex: startIdx,
            translation: dragTranslation,
            rowStride: Self.rowStride,
            count: snapshot.count
        )

        // 写入模型
        var ids = snapshot.map(\.id)
        let moved = ids.remove(at: startIdx)
        ids.insert(moved, at: targetIdx)
        model.reorder(ids: ids)

        if reduceMotion {
            dragState = .idle
            dragTranslation = 0
            return
        }

        // 弹性沉降
        let targetTranslation = CGFloat(targetIdx - startIdx) * Self.rowStride
        dragState = .settling(snapshot: snapshot, activeID: activeID, startIndex: startIdx, targetIndex: targetIdx)

        withAnimation(.spring(duration: 0.40, bounce: 0.20)) {
            dragTranslation = targetTranslation
        }

        let workItem = DispatchWorkItem { [self] in
            dragState = .idle
            dragTranslation = 0
        }
        settlingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    // MARK: - 本地重排（不写模型）

    private func reorderInSnapshot() {
        guard case .dragging(let snapshot, _, let startIdx) = dragState else { return }

        let dest = ReorderLayout.destinationIndex(
            startIndex: startIdx,
            translation: dragTranslation,
            rowStride: Self.rowStride,
            count: snapshot.count
        )

        guard dest != startIdx else { return }

        var updated = snapshot
        let item = updated.remove(at: startIdx)
        updated.insert(item, at: dest)
        dragState = .dragging(snapshot: updated, activeID: activeTaskID!, startIndex: dest)
        dragTranslation = 0
    }

    private func totalHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * Self.rowHeight + CGFloat(count - 1) * Self.rowSpacing
    }
}

// MARK: - 布局工具

enum ReorderLayout {
    static func destinationIndex(
        startIndex: Int,
        translation: CGFloat,
        rowStride: CGFloat,
        count: Int
    ) -> Int {
        guard count > 0, rowStride > 0 else { return 0 }
        let raw = CGFloat(startIndex) + translation / rowStride
        let rounded = Int((raw + 0.5).rounded(.down))
        return min(max(rounded, 0), count - 1)
    }

    static func neighborOffset(
        itemIndex: Int,
        startIndex: Int,
        translation: CGFloat,
        rowStride: CGFloat
    ) -> CGFloat {
        if translation > 0, itemIndex > startIndex {
            let dist = CGFloat(itemIndex - startIndex - 1) * rowStride
            return -min(max(translation - dist, 0), rowStride)
        }
        if translation < 0, itemIndex < startIndex {
            let dist = CGFloat(startIndex - itemIndex - 1) * rowStride
            return min(max(-translation - dist, 0), rowStride)
        }
        return 0
    }
}
