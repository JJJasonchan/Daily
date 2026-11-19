import DailyCore
import SwiftUI

enum TaskRowState {
    static func canEdit(isCompleted: Bool) -> Bool {
        !isCompleted
    }
}

struct TaskRow: View {
    static let rowHeight: CGFloat = 58
    static let cornerRadius: CGFloat = 15

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @FocusState private var isCheckboxFocused: Bool
    @GestureState private var isPressing = false
    @State private var isHovered = false

    let task: DailyTask
    let isCompleted: Bool
    let isRecurring: Bool
    let isDragSource: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: (DeleteScope) -> Void
    var metadataInteraction: TodayMetadataInteraction? = nil

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.physical, reduceMotion: reduceMotion)
    }

    private var canEdit: Bool {
        TaskRowState.canEdit(isCompleted: isCompleted)
    }

    private var rowOpacity: Double {
        isCompleted ? 0.65 : 1
    }

    var body: some View {
        if let metadataInteraction {
            row
                .onHover(perform: metadataInteraction.onHover)
                .accessibilityHidden(isDragSource)
                .fluidRowHighlight(
                    isHovered: false,
                    isFocused: metadataInteraction.focus.wrappedValue == task.id || isCheckboxFocused,
                    isEnabled: !isDragSource && !metadataInteraction.swipeOpen
                ) {
                    highlightedRow(metadataInteraction)
                }
        } else {
            row
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress(.space) {
                    onToggle()
                    return .handled
                }
                .onTapGesture(count: 2) {
                    guard canEdit else { return }
                    onEdit()
                }
                .onHover { isHovered = $0 }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressing) { _, pressing, _ in
                            pressing = true
                        }
                )
                .accessibilityLabel(accessibilitySummary)
                .accessibilityHint(canEdit ? "双击编辑" : "取消完成后可编辑")
                .fluidRowHighlight(
                    isHovered: isHovered,
                    isFocused: isFocused || isCheckboxFocused,
                    isEnabled: !isDragSource
                ) {
                    highlightedRow(nil)
                }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                checkboxImage(isHighlighted: false)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($isCheckboxFocused)
            .accessibilityLabel(isCompleted ? "标记为未完成" : "标记为完成")
            .accessibilityHint(task.titleSnapshot)
            .animation(motion.animation, value: isCompleted)

            if let metadataInteraction {
                metadataLabel(metadataInteraction)
            } else {
                taskLabel(isHighlighted: false)
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .opacity(rowOpacity)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isDragSource ? 0.14 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(isDragSource ? 0.24 : 0),
                    lineWidth: 0.5
                )
        }
        .scaleEffect(metadataInteraction == nil && isPressing ? motion.pressScale : 1)
        .shadow(
            color: .primary.opacity(isDragSource ? 0.18 : 0.06),
            radius: isDragSource ? 14 : 5,
            y: isDragSource ? 7 : 2
        )
        .animation(motion.animation, value: isCompleted)
        .animation(motion.animation, value: isPressing)
        .animation(motion.animation, value: isDragSource)
        .contextMenu {
            if canEdit {
                Button("编辑") { onEdit() }
                Divider()
            }
            if isRecurring {
                Button("仅移除今天", role: .destructive) {
                    onDelete(.todayOnly)
                }
                Button("停止以后重复", role: .destructive) {
                    onDelete(.allFuture)
                }
            } else {
                Button("删除任务", role: .destructive) {
                    onDelete(.todayOnly)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func checkboxImage(isHighlighted: Bool) -> some View {
        if metadataInteraction != nil, !isCompleted {
            TodayMetadataMark()
                .colorScheme(isHighlighted ? .dark : colorScheme)
        } else {
            legacyCheckboxImage(isHighlighted: isHighlighted)
        }
    }

    private func legacyCheckboxImage(isHighlighted: Bool) -> some View {
        let tint = isCompleted ? ColorTokens.checkboxComplete : ColorTokens.checkboxIncomplete
        return Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(isHighlighted ? Color.white : tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isCompleted)
            .scaleEffect(isCompleted ? 1.07 : 1)
            .frame(width: 28, height: 28)
    }

    private func highlightedRow(_ interaction: TodayMetadataInteraction?) -> some View {
        HStack(spacing: 12) {
            checkboxImage(isHighlighted: true)
            if let interaction {
                metadataContent(interaction, isHighlighted: true)
            } else {
                taskLabel(isHighlighted: true)
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .opacity(rowOpacity)
    }

    private func metadataContent(_ interaction: TodayMetadataInteraction, isHighlighted: Bool) -> some View {
        let metadata = TodayTaskMetadata(task: task)
        return TodayMetadataLayout(progress: interaction.progress) {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.titleSnapshot)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isHighlighted ? Color.white : .primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: geometry.size.width, height: 20, alignment: .leading)
                        .mask {
                            let fade = min(1, 16 / max(1, geometry.size.width))
                            LinearGradient(
                                stops: [.init(color: .black, location: 1 - fade), .init(color: .clear, location: 1)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        }

                    if hasMetadata { metadataMarkers(isHighlighted: isHighlighted) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .clipped()
            }
            stackedBadge(metadata.priority, systemImage: "cellularbars")
            stackedBadge(metadata.date, systemImage: "calendar")
            stackedBadge(metadata.assignee, systemImage: "person")
        }
        .colorScheme(isHighlighted ? .dark : colorScheme)
    }

    private func metadataLabel(_ interaction: TodayMetadataInteraction) -> some View {
        let metadata = TodayTaskMetadata(task: task)
        return metadataContent(interaction, isHighlighted: false)
        .contentShape(Rectangle())
        .focusable(!isDragSource)
        .focusEffectDisabled()
        .focused(interaction.focus, equals: isDragSource ? nil : task.id)
        .onKeyPress(keys: [.return, .space, .escape], phases: .down) { press in
            if press.key == .escape {
                interaction.onDismiss()
            } else {
                interaction.onToggle(false)
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            interaction.onShowSwipe()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            interaction.onHideSwipe()
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .home, .end]) { press in
            interaction.onNavigate(press.key)
            return .handled
        }
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
                switch result {
                case .first:
                    if canEdit { onEdit() }
                case .second:
                    interaction.onToggle(true)
                }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilitySummary)，\(metadata.accessibilitySummary)")
        .accessibilityValue(interaction.swipeOpen ? "任务操作已展开" : interaction.expanded ? "标签已展开" : "标签已收起")
        .accessibilityHint("按下以固定或收起标签，双击编辑任务")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { interaction.onToggle(false) }
        .accessibilityAction(named: Text(interaction.swipeOpen ? "收起任务操作" : "显示任务操作")) {
            if interaction.swipeOpen { interaction.onHideSwipe() }
            else { interaction.onShowSwipe() }
        }
        .accessibilityAction(named: Text("编辑任务")) {
            if canEdit { onEdit() }
        }
    }

    private func stackedBadge(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 12)
                .layoutPriority(1)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 25, maxHeight: 25)
        .background {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay { Capsule().fill(.primary.opacity(0.08)) }
        }
        .overlay { Capsule().strokeBorder(.background, lineWidth: 1.5) }
        .clipped()
        .allowsHitTesting(false)
    }

    private func taskLabel(isHighlighted: Bool) -> some View {
        let secondary = isHighlighted ? Color.white.opacity(0.75) : .secondary
        let primary = isHighlighted ? Color.white : .primary

        return VStack(alignment: .leading, spacing: 4) {
            Text(task.titleSnapshot)
                .font(.body.weight(.medium))
                .foregroundStyle(isCompleted ? secondary : primary)
                .strikethrough(isCompleted, color: secondary)
                .scaleEffect(isCompleted ? 0.92 : 1)
                .lineLimit(2)

            if hasMetadata {
                metadataMarkers(isHighlighted: isHighlighted)
            }
        }
    }

    private var hasMetadata: Bool {
        isRecurring || reminderText != nil || task.rolloverCount > 0
    }

    private func metadataMarkers(isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            if isRecurring {
                metadataEmojiBadge("🔁 重复", isHighlighted: isHighlighted)
            }
            if let reminderText {
                metadataEmojiBadge("⏰ \(reminderText)", isHighlighted: isHighlighted)
            }
            if task.rolloverCount > 0 {
                metadataEmojiBadge("➡️ 顺延 \(task.rolloverCount) 天", isHighlighted: isHighlighted)
            }
        }
    }

    private func metadataEmojiBadge(_ text: String, isHighlighted: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isHighlighted ? Color.white.opacity(0.75) : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                Capsule(style: .continuous)
                    .fill(isHighlighted ? Color.white.opacity(0.10) : Color.primary.opacity(0.06))
            }
            .accessibilityHidden(true)
    }

    private var reminderText: String? {
        guard
            task.reminderMode != .none,
            let hour = task.reminderHour,
            let minute = task.reminderMinute
        else {
            return nil
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private var accessibilitySummary: String {
        var values = [task.titleSnapshot, isCompleted ? "已完成" : "未完成"]
        if isRecurring {
            values.append("重复任务")
        }
        if let reminderText {
            values.append("提醒时间 \(reminderText)")
        }
        if task.rolloverCount > 0 {
            values.append("已顺延 \(task.rolloverCount) 天")
        }
        return values.joined(separator: "，")
    }
}
