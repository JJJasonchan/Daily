import DailyCore
import SwiftUI

extension TaskPriority {
    var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

enum TaskEditorScheduleState {
    static func initialDay(task: DailyTask?, template: TaskTemplate?, today: LocalDay) -> LocalDay {
        if template?.kind == .recurring, let startDay = template?.recurrence?.startDay {
            return startDay
        }
        return task.map { LocalDay(rawValue: $0.dayKey) } ?? today
    }
}

enum TaskEditorMode: Equatable {
    case newTask
    case template
    case taskWithTemplate
    case orphanInstance

    static func resolve(
        task: DailyTask?,
        template: TaskTemplate?
    ) -> TaskEditorMode {
        if task != nil {
            return template == nil ? .orphanInstance : .taskWithTemplate
        }
        return template == nil ? .newTask : .template
    }

    var title: String {
        switch self {
        case .newTask: "新建任务"
        case .template, .taskWithTemplate: "编辑任务"
        case .orphanInstance: "仅编辑今天的任务"
        }
    }

    var showsRecurrence: Bool { self != .orphanInstance }
}

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    let task: DailyTask?
    let template: TaskTemplate?
    let mode: TaskEditorMode
    let editsRecurringRule: Bool
    private let startsRecurring: Bool

    @State private var title: String
    @State private var priority: TaskPriority?
    @State private var assignee: String
    @State private var kind: TaskKind
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var selectedWeekdays: Set<Int>
    @State private var dayOfMonth: Int?
    @State private var scheduledDate: Date
    @State private var customDate: Date
    @State private var showsDatePicker = false
    @State private var reminderMode: ReminderMode
    @State private var reminderTime: Date
    @State private var isSaving = false

    init(model: AppModel, task: DailyTask? = nil) {
        self.init(model: model, task: task, template: nil)
    }

    init(model: AppModel, startsRecurring: Bool) {
        self.init(model: model, task: nil, template: nil, startsRecurring: startsRecurring)
    }

    init(model: AppModel, template: TaskTemplate) {
        self.init(model: model, task: nil, template: template)
    }

    private init(
        model: AppModel,
        task: DailyTask?,
        template: TaskTemplate?,
        startsRecurring: Bool = false
    ) {
        self.model = model
        self.startsRecurring = startsRecurring
        self.task = task
        self.template = template

        let resolvedTemplate = template ?? task.flatMap { item in
            model.editorTemplate(for: item)
        }
        mode = TaskEditorMode.resolve(task: task, template: resolvedTemplate)
        editsRecurringRule = resolvedTemplate?.kind == .recurring
        let recurrence = resolvedTemplate?.recurrence
        let hour = task?.reminderHour ?? resolvedTemplate?.reminderHour ?? 9
        let minute = task?.reminderMinute ?? resolvedTemplate?.reminderMinute ?? 0
        let time = Calendar.autoupdatingCurrent.date(
            from: DateComponents(hour: hour, minute: minute)
        ) ?? .now

        _title = State(initialValue: task?.titleSnapshot ?? resolvedTemplate?.title ?? "")
        _priority = State(initialValue: task == nil ? resolvedTemplate?.priority : task?.priority)
        _assignee = State(initialValue: (task == nil ? resolvedTemplate?.assignee : task?.assignee) ?? "")
        _kind = State(initialValue: resolvedTemplate?.kind ?? (startsRecurring ? .recurring : .once))
        _recurrenceFrequency = State(initialValue: recurrence?.frequency ?? .daily)
        _selectedWeekdays = State(initialValue: recurrence?.weekdays ?? [])
        _dayOfMonth = State(initialValue: recurrence?.dayOfMonth)
        let calendar = Calendar.autoupdatingCurrent
        let initialDay = TaskEditorScheduleState.initialDay(
            task: task, template: resolvedTemplate, today: model.currentDay
        )
        _scheduledDate = State(initialValue: initialDay.date(in: calendar))
        _customDate = State(initialValue: max(initialDay, model.currentDay).date(in: calendar))
        _reminderMode = State(
            initialValue: task?.reminderMode ?? resolvedTemplate?.reminderMode ?? .none
        )
        _reminderTime = State(initialValue: time)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editorTitle)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("名称")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                TextField("要做什么？", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("名称")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Form {
                Section {
                    Picker("优先级", selection: $priority) {
                        Text("未设置").tag(nil as TaskPriority?)
                        ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                            Text(priority.displayName).tag(Optional(priority))
                        }
                    }
                    TextField("负责人", text: $assignee)
                }

                if mode.showsRecurrence {
                    Section {
                        dateMenu
                        Picker("重复", selection: repetition) {
                            if !startsRecurring {
                                Text("不重复").tag(nil as RecurrenceFrequency?)
                            }
                            Text("每天").tag(Optional(RecurrenceFrequency.daily))
                            Text("工作日").tag(Optional(RecurrenceFrequency.weekdays))
                            Text("指定星期").tag(Optional(RecurrenceFrequency.selectedWeekdays))
                            Text("每月").tag(Optional(RecurrenceFrequency.monthly))
                        }
                        if kind == .recurring && recurrenceFrequency == .selectedWeekdays {
                            weekdayPicker
                        }
                        if kind == .recurring && recurrenceFrequency == .monthly {
                            Picker("每月日期", selection: $dayOfMonth) {
                                Text("月末最后一天").tag(nil as Int?)
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day) 日").tag(Optional(day))
                                }
                            }
                            if let dayOfMonth, dayOfMonth > 28 {
                                Text("当月没有所选日期时，在月末执行。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("提醒") {
                    Picker("提醒方式", selection: $reminderMode) {
                        Text("不提醒").tag(ReminderMode.none)
                        Text("提醒一次").tag(ReminderMode.once)
                        Text("重复提醒").tag(ReminderMode.persistent)
                    }

                    if reminderMode != .none {
                        DatePicker(
                            "时间",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    if reminderMode == .persistent {
                        Text("从设定时间起每隔 \(model.persistentIntervalMinutes) 分钟提醒，任务当天最多 \(NotificationService.persistentRequestCount) 次。完成后停止。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                Button(task == nil && template == nil ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
            }
            .padding(20)
        }
        .frame(
            width: 500,
            height: 500
        )
        .tint(ColorTokens.accent)
        .accessibilityElement(children: .contain)
    }

    private var editorTitle: String {
        if startsRecurring { return "新建重复任务" }
        return editsRecurringRule ? "编辑重复规则" : mode.title
    }

    private var repetition: Binding<RecurrenceFrequency?> {
        Binding(
            get: { kind == .recurring ? recurrenceFrequency : nil },
            set: { value in
                if let value {
                    kind = .recurring
                    recurrenceFrequency = value
                } else {
                    kind = .once
                    scheduledDate = max(scheduledDate, todayDate)
                }
            }
        )
    }

    private var todayDate: Date {
        model.currentDay.date(in: .autoupdatingCurrent)
    }

    private var dateMenu: some View {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = model.currentDay.adding(days: 1, calendar: calendar).date(in: calendar)
        let label = kind == .recurring ? "开始日期" : "安排日期"
        let formattedDate = scheduledDate == todayDate ? "今天"
            : scheduledDate == tomorrow ? "明天"
            : scheduledDate.formatted(.dateTime.year().month().day())

        return LabeledContent(label) {
            Menu(formattedDate) {
                Button("今天") { scheduledDate = todayDate }
                Button("明天") { scheduledDate = tomorrow }
                Button("选择日期…") {
                    customDate = max(scheduledDate, todayDate)
                    showsDatePicker = true
                }
            }
            .accessibilityLabel(label)
            .accessibilityValue(formattedDate)
            .popover(isPresented: $showsDatePicker) {
                VStack {
                    DatePicker(label, selection: $customDate, in: todayDate..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Button("确定") {
                        scheduledDate = customDate
                        showsDatePicker = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .frame(width: 285)
            }
        }
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

        Task { @MainActor in
            let result: MutationResult
            if let task, mode == .orphanInstance {
                result = await model.updateInstance(task, with: makeInstanceDraft())
            } else if let task {
                result = await model.update(task, with: makeDraft())
            } else if let template {
                result = await model.update(template, with: makeDraft())
            } else {
                result = await model.add(makeDraft())
            }
            isSaving = false
            if result.shouldDismissEditor {
                dismiss()
            }
        }
    }

    private func makeDraft() -> TaskDraft {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let scheduledDay = LocalDay(date: scheduledDate, calendar: calendar)
        let recurrence = kind == .recurring
            ? RecurrenceRule(
                frequency: recurrenceFrequency,
                weekdays: recurrenceFrequency == .selectedWeekdays ? selectedWeekdays : [],
                dayOfMonth: recurrenceFrequency == .monthly ? dayOfMonth : nil,
                startDay: scheduledDay
            )
            : nil

        return TaskDraft(
            title: title,
            kind: kind,
            recurrence: recurrence,
            scheduledDay: kind == .once ? scheduledDay : nil,
            reminderMode: reminderMode,
            reminderHour: reminderMode == .none ? nil : components.hour,
            reminderMinute: reminderMode == .none ? nil : components.minute,
            priority: priority,
            assignee: assignee
        )
    }

    private func makeInstanceDraft() -> InstanceDraft {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: reminderTime
        )
        return InstanceDraft(
            title: title,
            reminderMode: reminderMode,
            reminderHour: reminderMode == .none ? nil : components.hour,
            reminderMinute: reminderMode == .none ? nil : components.minute,
            priority: priority,
            assignee: assignee
        )
    }
}

private struct ConditionalProminentButtonStyle: PrimitiveButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            Button(configuration)
                .buttonStyle(.borderedProminent)
                .tint(ColorTokens.accent)
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
