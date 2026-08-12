import DailyCore
import SwiftUI

enum RuleReorderCoordinator {
    static func reordered(
        ids: [UUID],
        moving sourceID: UUID,
        before targetID: UUID
    ) -> [UUID]? {
        guard sourceID != targetID,
              let sourceIndex = ids.firstIndex(of: sourceID),
              let targetIndex = ids.firstIndex(of: targetID) else {
            return nil
        }
        var result = ids
        let source = result.remove(at: sourceIndex)
        result.insert(source, at: min(targetIndex, result.count))
        return result == ids ? nil : result
    }

    static func reordered(
        ids: [UUID],
        moving sourceID: UUID,
        offset: Int
    ) -> [UUID]? {
        guard let sourceIndex = ids.firstIndex(of: sourceID) else { return nil }
        let destination = sourceIndex + offset
        guard ids.indices.contains(destination) else { return nil }
        var result = ids
        result.swapAt(sourceIndex, destination)
        return result
    }
}

struct RulesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel
    @State private var dropTargetID: UUID?

    private var motion: MotionSpec {
        MotionTokens.resolved(MotionTokens.standard, reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if model.templates.isEmpty {
                ContentUnavailableView(
                    "没有重复规则",
                    systemImage: "repeat",
                    description: Text("在今日页面新建重复任务后，可在这里统一管理。")
                )
            } else {
                List {
                    Section("重复任务") {
                        ForEach(model.templates) { template in
                            ruleRow(template)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("重复规则")
        .focusEffectDisabled()
    }

    private func ruleRow(_ template: TaskTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
                .draggable(template.id.uuidString)
                .accessibilityLabel("拖动以重新排序 \(template.title)")

            VStack(spacing: 2) {
                Button {
                    _ = applyReorder(moving: template.id, offset: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(model.templates.first?.id == template.id)
                .accessibilityLabel("上移 \(template.title)")

                Button {
                    _ = applyReorder(moving: template.id, offset: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(model.templates.last?.id == template.id)
                .accessibilityLabel("下移 \(template.title)")
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(template.isEnabled ? .primary : .secondary)

                HStack(spacing: 10) {
                    Text(recurrenceDescription(template.recurrence))
                    Text(template.isEnabled ? "已启用" : "已停用")
                    if let reminder = reminderDescription(template) {
                        Label(reminder, systemImage: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "启用 \(template.title)",
                isOn: Binding(
                    get: { template.isEnabled },
                    set: { _ = model.setTemplateEnabled(template, enabled: $0) }
                )
            )
            .labelsHidden()

            Menu {
                Button("编辑") {
                    model.editorTemplateID = template.id
                }
                Button("删除规则", role: .destructive) {
                    _ = model.deleteTemplate(template)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("管理 \(template.title)")
        }
        .padding(.vertical, 5)
        .opacity(template.isEnabled ? 1 : 0.72)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(dropTargetID == template.id ? 0.08 : 0))
        )
        .animation(motion.animation, value: dropTargetID)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let sourceID = UUID(uuidString: value) else {
                return false
            }
            return applyReorder(moving: sourceID, before: template.id)
        } isTargeted: { isTargeted in
            dropTargetID = isTargeted ? template.id : nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "上移") {
            _ = applyReorder(moving: template.id, offset: -1)
        }
        .accessibilityAction(named: "下移") {
            _ = applyReorder(moving: template.id, offset: 1)
        }
    }

    private func applyReorder(moving sourceID: UUID, before targetID: UUID) -> Bool {
        guard let reordered = RuleReorderCoordinator.reordered(
            ids: model.templates.map(\.id),
            moving: sourceID,
            before: targetID
        ) else { return false }
        return model.reorderTemplates(ids: reordered) != .failure
    }

    private func applyReorder(moving sourceID: UUID, offset: Int) -> Bool {
        guard let reordered = RuleReorderCoordinator.reordered(
            ids: model.templates.map(\.id),
            moving: sourceID,
            offset: offset
        ) else { return false }
        return model.reorderTemplates(ids: reordered) != .failure
    }

    private func recurrenceDescription(_ recurrence: RecurrenceRule?) -> String {
        guard let recurrence else { return "未设置重复日期" }
        switch recurrence.frequency {
        case .daily:
            return "每天"
        case .weekdays:
            return "工作日"
        case .selectedWeekdays:
            let names = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
            return recurrence.weekdays.sorted().compactMap { names[$0] }.map { "周\($0)" }.joined(separator: "、")
        case .monthly:
            if let dom = recurrence.dayOfMonth {
                return "每月 \(dom) 日"
            } else {
                return "每月最后一天"
            }
        }
    }

    private func reminderDescription(_ template: TaskTemplate) -> String? {
        guard
            template.reminderMode != .none,
            let hour = template.reminderHour,
            let minute = template.reminderMinute
        else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}
