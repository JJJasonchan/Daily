import DailyCore
import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    let task: DailyTask?

    @State private var title: String
    @State private var kind: TaskKind
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var selectedWeekdays: Set<Int>
    @State private var reminderMode: ReminderMode
    @State private var reminderTime: Date
    @State private var isSaving = false

    init(model: AppModel, task: DailyTask? = nil) {
        self.model = model
        self.task = task

        let template = task.flatMap { item in
            model.templates.first { $0.id == item.templateID }
        }
        let recurrence = template?.recurrence
        let hour = task?.reminderHour ?? template?.reminderHour ?? 9
        let minute = task?.reminderMinute ?? template?.reminderMinute ?? 0
        let time = Calendar.autoupdatingCurrent.date(
            from: DateComponents(hour: hour, minute: minute)
        ) ?? .now

        _title = State(initialValue: task?.titleSnapshot ?? "")
        _kind = State(initialValue: template?.kind ?? .once)
        _recurrenceFrequency = State(initialValue: recurrence?.frequency ?? .daily)
        _selectedWeekdays = State(initialValue: recurrence?.weekdays ?? [])
        _reminderMode = State(
            initialValue: task?.reminderMode ?? template?.reminderMode ?? .none
        )
        _reminderTime = State(initialValue: time)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(task == nil ? "新建任务" : "编辑任务")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭编辑器")
            }
            .padding(20)

            Divider()

            Form {
                TextField("任务标题", text: $title)
                    .accessibilityLabel("任务标题")

                Picker("任务类型", selection: $kind) {
                    Text("仅今天").tag(TaskKind.once)
                    Text("重复").tag(TaskKind.recurring)
                }
                .pickerStyle(.segmented)

                if kind == .recurring {
                    Section("重复规则") {
                        Picker("频率", selection: $recurrenceFrequency) {
                            Text("每天").tag(RecurrenceFrequency.daily)
                            Text("工作日").tag(RecurrenceFrequency.weekdays)
                            Text("选择星期").tag(RecurrenceFrequency.selectedWeekdays)
                        }

                        if recurrenceFrequency == .selectedWeekdays {
                            weekdayPicker
                        }
                    }
                }

                Section("提醒") {
                    Picker("提醒方式", selection: $reminderMode) {
                        Text("不提醒").tag(ReminderMode.none)
                        Text("提醒一次").tag(ReminderMode.once)
                        Text("持续提醒").tag(ReminderMode.persistent)
                    }

                    if reminderMode != .none {
                        DatePicker(
                            "时间",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(task == nil ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
            }
            .padding(20)
        }
        .frame(width: 470, height: kind == .recurring ? 560 : 420)
        .accessibilityElement(children: .contain)
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(weekdayChoices, id: \.value) { weekday in
                Button {
                    if selectedWeekdays.contains(weekday.value) {
                        selectedWeekdays.remove(weekday.value)
                    } else {
                        selectedWeekdays.insert(weekday.value)
                    }
                } label: {
                    Text(weekday.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    .borderedProminentIf(selectedWeekdays.contains(weekday.value))
                )
                .accessibilityLabel("星期\(weekday.label)")
                .accessibilityValue(
                    selectedWeekdays.contains(weekday.value) ? "已选择" : "未选择"
                )
            }
        }
    }

    private var weekdayChoices: [(value: Int, label: String)] {
        [
            (2, "一"), (3, "二"), (4, "三"), (5, "四"),
            (6, "五"), (7, "六"), (1, "日")
        ]
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(kind == .recurring
                && recurrenceFrequency == .selectedWeekdays
                && selectedWeekdays.isEmpty)
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        model.clearError()
        let draft = makeDraft()

        Task { @MainActor in
            if let task {
                await model.update(task, with: draft)
            } else {
                await model.add(draft)
            }
            isSaving = false
            if model.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func makeDraft() -> TaskDraft {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let recurrence = kind == .recurring
            ? RecurrenceRule(
                frequency: recurrenceFrequency,
                weekdays: recurrenceFrequency == .selectedWeekdays ? selectedWeekdays : [],
                startDay: LocalDay(date: .now, calendar: calendar)
            )
            : nil

        return TaskDraft(
            title: title,
            kind: kind,
            recurrence: recurrence,
            reminderMode: reminderMode,
            reminderHour: reminderMode == .none ? nil : components.hour,
            reminderMinute: reminderMode == .none ? nil : components.minute
        )
    }
}

private struct ConditionalProminentButtonStyle: PrimitiveButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            Button(configuration)
                .buttonStyle(.borderedProminent)
                .tint(.primary)
        } else {
            Button(configuration)
                .buttonStyle(.bordered)
        }
    }
}

private extension PrimitiveButtonStyle where Self == ConditionalProminentButtonStyle {
    static func borderedProminentIf(_ condition: Bool) -> Self {
        ConditionalProminentButtonStyle(isProminent: condition)
    }
}
