import DailyCore
import SwiftUI

enum TaskRowState {
    static func canEdit(isCompleted: Bool) -> Bool {
        !isCompleted
    }
}

struct TaskRow: View {
    static let rowHeight: CGFloat = 58

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @GestureState private var isPressing = false
    @State private var isHovered = false
    @State private var completionHighlight = false

    let task: DailyTask
    let isCompleted: Bool
    let isRecurring: Bool
    let isDragSource: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: (DeleteScope) -> Void

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    private var canEdit: Bool {
        TaskRowState.canEdit(isCompleted: isCompleted)
    }

    private var backgroundOpacity: Double {
        if isDragSource { return 0.14 }
        if isHovered { return 0.07 }
        return 0.0
    }

    private var borderOpacity: Double {
        if isDragSource { return 0.24 }
        if isHovered { return 0.12 }
        return 0.0
    }

    private var rowOpacity: Double {
        isCompleted ? 0.65 : 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isCompleted ? ColorTokens.checkboxComplete : ColorTokens.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isCompleted)
                    .scaleEffect(isCompleted ? 1.07 : 1)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "标记为未完成" : "标记为完成")
            .accessibilityHint(task.titleSnapshot)
            .animation(motion.animation, value: isCompleted)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.titleSnapshot)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
                    .scaleEffect(isCompleted ? 0.92 : 1)
                    .lineLimit(2)

                if hasMetadata {
                    HStack(spacing: 6) {
                        if isRecurring {
                            metadataEmojiBadge("🔁 重复")
                        }
                        if let reminderText {
                            metadataEmojiBadge("⏰ \(reminderText)")
                        }
                        if task.rolloverCount > 0 {
                            metadataEmojiBadge("➡️ 顺延 \(task.rolloverCount) 天")
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .opacity(rowOpacity)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.primary.opacity(backgroundOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(borderOpacity),
                    lineWidth: 0.5
                )
        }
        .overlay {
            if isHovered && !isDragSource {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .primary.opacity(0.12),
                                .clear,
                                .primary.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
        }
        .scaleEffect(isPressing ? motion.pressScale : 1)
        .offset(y: isHovered && !isDragSource ? motion.hoverLift : 0)
        .shadow(
            color: .primary.opacity(isDragSource ? 0.18 : 0.06),
            radius: isDragSource ? 14 : 5,
            y: isDragSource ? 7 : 2
        )
        .animation(motion.animation, value: isCompleted)
        .animation(motion.animation, value: isPressing)
        .animation(motion.animation, value: isHovered)
        .animation(motion.animation, value: isDragSource)
        .animation(motion.animation, value: isFocused)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
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
        .overlay {
            if completionHighlight {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .animation(.easeOut(duration: 0.4), value: completionHighlight)
            }
        }
        .onChange(of: isCompleted) { _, _ in
            completionHighlight = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.25))
                completionHighlight = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(canEdit ? "双击编辑" : "取消完成后可编辑")
    }

    private var hasMetadata: Bool {
        isRecurring || reminderText != nil || task.rolloverCount > 0
    }

    private func metadataBadge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .accessibilityHidden(true)
    }

    private func metadataEmojiBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
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
