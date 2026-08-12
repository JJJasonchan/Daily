import DailyCore
import SwiftUI

struct RulesView: View {
    @Bindable var model: AppModel

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
                        .onMove(perform: move)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("重复规则")
    }

    private func ruleRow(_ template: TaskTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .contain)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = model.templates
        reordered.move(fromOffsets: source, toOffset: destination)
        _ = model.reorderTemplates(ids: reordered.map(\.id))
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
