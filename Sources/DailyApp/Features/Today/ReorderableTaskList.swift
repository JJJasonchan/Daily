import AppKit
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel

    let isCompleted: (DailyTask) -> Bool
    let onToggle: (DailyTask) -> Void
    let onEdit: (DailyTask) -> Void
    let onDelete: (DailyTask, DeleteScope) -> Void
    let onSwipeDelete: @MainActor (DailyTask) async -> Void

    // 拖拽状态机
    enum DragState: Equatable {
        case idle
        case dragging(snapshot: [DailyTask], activeID: UUID, startIndex: Int)
        case settling(snapshot: [DailyTask], activeID: UUID, startIndex: Int, targetIndex: Int)
    }

    @State private var dragState: DragState = .idle
    @State private var dragTranslation: CGFloat = 0
    @State private var settlingWorkItem: DispatchWorkItem?
    @State private var openSwipeID: UUID?
    @State private var swipeDrag: SwipeDrag?
    @State private var ignoredSwipeID: UUID?
    @State private var swipeExposure: CGFloat = 0
    @State private var committingSwipeID: UUID?
    @State private var foldingSwipeID: UUID?
    @State private var swipeCommitTask: Task<Void, Never>?
    @State private var rowWidth: CGFloat = 0
    @Namespace private var dragSpace

    private struct SwipeDrag {
        let taskID: UUID
        let startedOpen: Bool
        let grabX: CGFloat
    }

    private var swipeLayout: TodaySwipeLayout { TodaySwipeLayout(rowWidth: rowWidth) }
    @State private var hasEntered = false
    @State private var metadata = TodayMetadataSelection()
    @State private var metadataAnimation = TodayMetadataAnimation()
    @FocusState private var metadataFocus: UUID?

    var body: some View {
        let tasks = visibleTasks
        let activeID = activeTaskID
        let startIndex = dragStartIndex

        ZStack(alignment: .topLeading) {
            // 底层：所有任务行（被拖的行透明度=0）
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    taskRow(task, isDragging: activeID == task.id)
                        .opacity(activeID == task.id ? 0 : entranceOpacity)
                        .offset(y: neighborYOffset(index: index) + entranceOffset(index))
                        .animation(
                            reduceMotion
                                ? nil
                                : .spring(duration: 0.40, bounce: 0.16)
                                    .delay(Double(index) * 0.045),
                            value: hasEntered
                        )
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
        .frame(height: totalHeight(for: tasks.count) - (tasks.contains { $0.id == foldingSwipeID } ? Self.rowHeight : 0), alignment: .top)
        .coordinateSpace(name: dragSpace)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .background {
            TodayMetadataDisplayDriver(animation: metadataAnimation)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: metadataFocus) { _, next in
            let pointerEvents: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            let viaPointer = NSApp.currentEvent.map { pointerEvents.contains($0.type) } ?? false
            if let openSwipeID, let next, openSwipeID != next { closeSwipe() }
            metadata.focus(next, viaPointer: viaPointer)
            updateMetadataAnimation()
        }
        .onChange(of: tasks.map(\.id)) { _, ids in
            if let openSwipeID, !ids.contains(openSwipeID) { closeSwipe() }
            if let swipeDrag, !ids.contains(swipeDrag.taskID) { self.swipeDrag = nil }
            if let committingSwipeID, !ids.contains(committingSwipeID) { self.committingSwipeID = nil }
            metadata.keep(Set(ids))
            updateMetadataAnimation()
        }
        .onChange(of: allowsMetadataExpansion) { _, _ in updateMetadataAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateMetadataAnimation() }
        .onDisappear {
            settlingWorkItem?.cancel()
            swipeCommitTask?.cancel()
            swipeCommitTask = nil
            committingSwipeID = nil
            foldingSwipeID = nil
            swipeDrag = nil
            ignoredSwipeID = nil
            closeSwipe()
            metadata = TodayMetadataSelection()
            metadataAnimation.reset()
        }
        .onAppear {
            guard !hasEntered else { return }
            if reduceMotion {
                hasEntered = true
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation {
                        hasEntered = true
                    }
                }
            }
        }
    }

    // MARK: - 入场动画

    private var entranceOpacity: Double {
        reduceMotion || hasEntered ? 1 : 0
    }

    private func entranceOffset(_ index: Int) -> CGFloat {
        guard !reduceMotion, !hasEntered else { return 0 }
        return 10
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
            return model.todayTasks.filter { !isCompleted($0) }
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

    // MARK: - Task metadata

    private var allowsMetadataExpansion: Bool {
        dragState == .idle && openSwipeID == nil && swipeDrag == nil && committingSwipeID == nil
    }

    private func updateMetadataAnimation() {
        metadataAnimation.setTarget(allowsMetadataExpansion ? metadata.expanded : nil, reduceMotion: reduceMotion)
    }

    private func moveMetadataFocus(from taskID: UUID, by key: KeyEquivalent) {
        let ids = visibleTasks.map(\.id)
        guard let index = ids.firstIndex(of: taskID) else { return }
        let next: Int
        switch key {
        case .upArrow: next = (index - 1 + ids.count) % ids.count
        case .downArrow: next = (index + 1) % ids.count
        case .home: next = 0
        case .end: next = ids.count - 1
        default: return
        }
        metadataFocus = ids[next]
        metadata.focus(ids[next], viaPointer: false)
        updateMetadataAnimation()
    }

    private func metadataInteraction(for taskID: UUID, isDragging: Bool) -> TodayMetadataInteraction {
        TodayMetadataInteraction(
            focus: $metadataFocus,
            progress: isDragging ? 0 : metadataAnimation.progress[taskID, default: 0],
            expanded: allowsMetadataExpansion && metadata.expanded == taskID,
            onHover: { inside in
                guard !isDragging else { return }
                metadata.hover(taskID, inside: inside)
                updateMetadataAnimation()
            },
            onToggle: { viaPointer in
                guard allowsMetadataExpansion else { return }
                metadata.toggle(taskID, viaPointer: viaPointer)
                updateMetadataAnimation()
            },
            onNavigate: { moveMetadataFocus(from: taskID, by: $0) },
            onDismiss: {
                if openSwipeID != nil {
                    closeSwipe()
                } else {
                    metadata.dismiss()
                    updateMetadataAnimation()
                }
            },
            swipeOpen: openSwipeID == taskID,
            onShowSwipe: {
                guard dragState == .idle, swipeDrag == nil, committingSwipeID == nil else { return }
                settleSwipe(open: taskID)
            },
            onHideSwipe: {
                guard openSwipeID == taskID else { return }
                closeSwipe()
            }
        )
    }

    // MARK: - Row

    private func taskRow(_ task: DailyTask, isDragging: Bool) -> some View {
        let exposure = exposure(for: task.id)
        return ZStack(alignment: .trailing) {
            swipeDrawer(for: task, exposure: exposure)

            TaskRow(
                task: task,
                isCompleted: isCompleted(task),
                isRecurring: model.templates.first { $0.id == task.templateID }?.kind == .recurring,
                isDragSource: isDragging,
                onToggle: { onToggle(task) },
                onEdit: {
                    closeSwipe()
                    onEdit(task)
                },
                onDelete: { scope in onDelete(task, scope) },
                metadataInteraction: metadataInteraction(for: task.id, isDragging: isDragging)
            )
            .offset(x: -exposure)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(dragSpace))
                    .onChanged { value in handleRowDragChanged(value, task: task) }
                    .onEnded { value in handleRowDragEnded(value, task: task) }
            )
        }
        .frame(height: Self.rowHeight)
        .frame(height: foldingSwipeID == task.id ? 0 : Self.rowHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: TaskRow.cornerRadius, style: .continuous))
        .onKeyPress(.escape) {
            guard openSwipeID == task.id else { return .ignored }
            closeSwipe()
            return .handled
        }
    }

    // MARK: - Swipe actions

    private func exposure(for id: UUID) -> CGFloat {
        if committingSwipeID == id { return rowWidth }
        if swipeDrag?.taskID == id { return swipeExposure }
        return openSwipeID == id ? swipeLayout.drawerWidth : 0
    }

    private func swipeDrawer(for task: DailyTask, exposure: CGFloat) -> some View {
        let width = swipeLayout.actionWidth
        let armed = committingSwipeID == task.id || (
            swipeDrag?.taskID == task.id && swipeLayout.canCommit && exposure >= swipeLayout.commitPoint
        )
        let interactive = openSwipeID == task.id && swipeDrag == nil && committingSwipeID == nil
        return HStack(spacing: 0) {
            Button {
                closeSwipe()
                onEdit(task)
            } label: {
                swipeLabel("编辑", icon: "pencil", width: width)
            }
            .background(Color(nsColor: .darkGray))

            Button {
                commitSwipe(task)
            } label: {
                swipeLabel(armed && committingSwipeID != task.id ? "松开删除" : "删除", icon: "trash", width: armed ? exposure : width)
            }
            .background(Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: exposure, height: Self.rowHeight, alignment: .trailing)
        .clipped()
        .allowsHitTesting(interactive)
        .accessibilityHidden(!interactive)
    }

    private func swipeLabel(_ title: String, icon: String, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .frame(width: width, height: Self.rowHeight)
        .contentShape(Rectangle())
    }

    private func settleSwipe(open id: UUID?, speed: CGFloat = 0) {
        let flick = abs(speed) >= TodaySwipeLayout.flickSpeed
        withAnimation(reduceMotion ? nil : .spring(duration: flick ? 0.4 : 0.3, bounce: flick ? 0.2 : 0)) {
            openSwipeID = id
            swipeDrag = nil
            swipeExposure = 0
        }
    }

    private func closeSwipe() {
        settleSwipe(open: nil)
    }

    private func commitSwipe(_ task: DailyTask) {
        guard committingSwipeID == nil else { return }
        let animate = !reduceMotion
        let requiresScope = model.templates.first { $0.id == task.templateID }?.kind == .recurring
        let transition: Animation? = animate ? .easeOut(duration: 0.2) : nil
        withAnimation(transition) {
            committingSwipeID = task.id
            openSwipeID = nil
            swipeDrag = nil
        }
        swipeCommitTask = Task { @MainActor in
            defer {
                withAnimation(transition) {
                    committingSwipeID = nil
                    foldingSwipeID = nil
                }
                swipeCommitTask = nil
            }

            if animate {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    if !requiresScope {
                        withAnimation(transition) { foldingSwipeID = task.id }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, committingSwipeID == task.id else { return }
            await onSwipeDelete(task)
        }
    }

    // MARK: - 手势处理

    private func handleRowDragChanged(_ value: DragGesture.Value, task: DailyTask) {
        guard committingSwipeID == nil, ignoredSwipeID != task.id else { return }
        if let swipeDrag {
            guard swipeDrag.taskID == task.id else { return }
            let start = swipeDrag.startedOpen ? swipeLayout.drawerWidth : 0
            swipeExposure = swipeLayout.exposure(for: start - (value.translation.width - swipeDrag.grabX))
            return
        }

        switch dragState {
        case .idle:
            let dx = value.translation.width
            let dy = value.translation.height
            let threshold = TodaySwipeLayout.gestureThreshold
            guard max(abs(dx), abs(dy)) >= threshold else { return }
            if abs(dx) > abs(dy) {
                let startedOpen = openSwipeID == task.id
                guard dx < 0 || startedOpen else {
                    if openSwipeID != nil { closeSwipe() }
                    ignoredSwipeID = task.id
                    return
                }
                let grabX = dx < 0 ? -threshold : threshold
                openSwipeID = nil
                swipeDrag = SwipeDrag(taskID: task.id, startedOpen: startedOpen, grabX: grabX)
                let start = startedOpen ? swipeLayout.drawerWidth : 0
                swipeExposure = swipeLayout.exposure(for: start - (dx - grabX))
                return
            }
            closeSwipe()
            let snapshot = visibleTasks
            guard let idx = snapshot.firstIndex(where: { $0.id == task.id }) else { return }
            dragState = .dragging(snapshot: snapshot, activeID: task.id, startIndex: idx)
            dragTranslation = 0
        case .settling:
            settlingWorkItem?.cancel()
            settlingWorkItem = nil
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
        if ignoredSwipeID == task.id {
            ignoredSwipeID = nil
            return
        }
        if swipeDrag?.taskID == task.id {
            if swipeLayout.canCommit && swipeExposure >= swipeLayout.commitPoint {
                commitSwipe(task)
            } else {
                let speed = -value.velocity.width
                let open = swipeLayout.shouldStayOpen(exposure: swipeExposure, speed: speed)
                settleSwipe(open: open ? task.id : nil, speed: speed)
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
        model.reorder(ids: ReorderLayout.mergingVisibleOrder(ids, into: model.todayTasks.map(\.id)))

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
    static func mergingVisibleOrder(_ reorderedIDs: [UUID], into currentIDs: [UUID]) -> [UUID] {
        let current = Set(currentIDs)
        let reordered = reorderedIDs.filter { current.contains($0) }
        let visible = Set(reordered)
        var iterator = reordered.makeIterator()
        return currentIDs.map { id in
            visible.contains(id) ? iterator.next() ?? id : id
        }
    }

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
