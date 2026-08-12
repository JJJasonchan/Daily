import DailyCore
import SwiftUI

struct TaskRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool
    @GestureState private var isPressing = false
    @State private var isHovered = false

    let task: DailyTask
    let isCompleted: Bool
    let isDragSource: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "标记为未完成" : "标记为完成")
            .accessibilityHint(task.titleSnapshot)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.titleSnapshot)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
                    .lineLimit(2)

                if hasMetadata {
                    HStack(spacing: 10) {
                        if let reminderText {
                            Label(reminderText, systemImage: "bell")
                        }
                        if task.rolloverCount > 0 {
                            Label("已顺延 \(task.rolloverCount) 天", systemImage: "arrow.forward")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
                .gesture(reorderGesture)
                .accessibilityLabel("拖动以重新排序 \(task.titleSnapshot)")
                .accessibilityHint("按住后上下拖动")
        }
        .padding(.horizontal, 14)
        .frame(height: ReorderableTaskList.rowHeight)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .glassModule(
            interactive: true,
            tint: isCompleted ? Color.secondary.opacity(0.08) : nil,
            cornerRadius: 15
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    contrast == .increased ? Color.primary : Color.accentColor,
                    lineWidth: isFocused ? 2 : 0
                )
                .padding(1)
        }
        .opacity(isCompleted ? 0.78 : 1)
        .scaleEffect(isPressing ? motion.pressScale : 1)
        .offset(y: isHovered && !isDragSource ? motion.hoverLift : 0)
        .shadow(
            color: .black.opacity(isDragSource ? 0.18 : 0.06),
            radius: isDragSource ? 14 : 5,
            y: isDragSource ? 7 : 2
        )
        .animation(motion.animation, value: isCompleted)
        .animation(motion.animation, value: isPressing)
        .animation(motion.animation, value: isHovered)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.space) {
            onToggle()
            return .handled
        }
        .onTapGesture(count: 2, perform: onEdit)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressing) { _, pressing, _ in
                    pressing = true
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var reorderGesture: some Gesture {
        DragGesture(
            minimumDistance: 6,
            coordinateSpace: .named(ReorderableTaskList.coordinateSpaceName)
        )
        .onChanged(onDragChanged)
        .onEnded(onDragEnded)
    }

    private var hasMetadata: Bool {
        reminderText != nil || task.rolloverCount > 0
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
        if let reminderText {
            values.append("提醒时间 \(reminderText)")
        }
        if task.rolloverCount > 0 {
            values.append("已顺延 \(task.rolloverCount) 天")
        }
        return values.joined(separator: "，")
    }
}
