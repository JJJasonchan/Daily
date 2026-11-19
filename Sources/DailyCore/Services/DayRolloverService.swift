import Foundation

@MainActor
public final class DayRolloverService {
    private let repository: TaskRepository
    private let notifications: NotificationScheduling
    private let dayProvider: DayProviding

    public init(
        repository: TaskRepository,
        notifications: NotificationScheduling,
        dayProvider: DayProviding
    ) {
        self.repository = repository
        self.notifications = notifications
        self.dayProvider = dayProvider
    }

    public func processThroughToday() async throws {
        let now = dayProvider.now
        let calendar = dayProvider.calendar
        let today = LocalDay(date: now, calendar: calendar)
        let settings = try repository.settings()
        let isFirstRun = settings.lastProcessedDayKey == nil
        let firstDay: LocalDay
        if let lastProcessedDayKey = settings.lastProcessedDayKey {
            firstDay = LocalDay(rawValue: lastProcessedDayKey).adding(days: 1, calendar: calendar)
        } else {
            firstDay = today
        }

        try reconcileFutureInstances(after: today, calendar: calendar)

        if firstDay <= today {
            let enabledTemplates = try repository.templates(enabledOnly: true)
            let templatesByID = Dictionary(
                uniqueKeysWithValues: enabledTemplates.map { ($0.id, $0) }
            )
            var existingKeys = Set(
                try repository.dailyTasks(from: firstDay, through: today).map(LogicalTaskKey.init)
            )
            var day = firstDay

            while day <= today {
                if !isFirstRun {
                    try rollIncompleteOneTimeTasks(
                        from: day.adding(days: -1, calendar: calendar),
                        to: day,
                        templatesByID: templatesByID,
                        existingKeys: &existingKeys,
                        now: now
                    )
                }
                generateRecurringTasks(
                    on: day,
                    templates: enabledTemplates,
                    calendar: calendar,
                    existingKeys: &existingKeys,
                    now: now
                )

                let previousDayKey = settings.lastProcessedDayKey
                settings.lastProcessedDayKey = day.rawValue
                do {
                    try repository.save()
                } catch {
                    settings.lastProcessedDayKey = previousDayKey
                    throw error
                }

                day = day.adding(days: 1, calendar: calendar)
            }
        }

        let incompleteUpcoming = try repository.dailyTasks(from: today).filter {
            $0.completedAt == nil
        }
        try await notifications.rebuild(tasks: incompleteUpcoming, settings: settings, now: now)
    }

    public func historyStatus(for task: DailyTask, allTasks: [DailyTask]) -> HistoryStatus {
        if task.completedAt != nil {
            return .completed
        }
        if allTasks.contains(where: { $0.rolloverOriginID == task.id }) {
            return .rolledOver
        }
        return .incomplete
    }

    private func reconcileFutureInstances(after day: LocalDay, calendar: Calendar) throws {
        let tomorrow = day.adding(days: 1, calendar: calendar)
        let tasks = try repository.dailyTasks(from: tomorrow)
        guard !tasks.isEmpty else { return }
        let templates = Dictionary(uniqueKeysWithValues: try repository.templates(enabledOnly: false).map { ($0.id, $0) })
        var didChange = false

        for (templateID, instances) in Dictionary(grouping: tasks, by: \.templateID) {
            let incomplete = instances.filter { $0.completedAt == nil }
            // Only recurring-rule deletion could leave a future instance without a template.
            guard let template = templates[templateID], template.isEnabled else {
                incomplete.forEach { repository.remove($0) }
                didChange = didChange || !incomplete.isEmpty
                continue
            }
            guard template.kind == .recurring,
                  let rule = template.recurrence,
                  rule.frequency == .monthly, rule.dayOfMonth == nil,
                  let nextDay = rule.firstOccurrence(onOrAfter: tomorrow, calendar: calendar)
            else { continue }

            var hasNextOccurrence = instances.contains { $0.dayKey == nextDay.rawValue }
            for task in incomplete where !rule.matches(LocalDay(rawValue: task.dayKey), calendar: calendar) {
                if hasNextOccurrence {
                    repository.remove(task)
                } else {
                    task.dayKey = nextDay.rawValue
                    task.originalDayKey = nextDay.rawValue
                    hasNextOccurrence = true
                }
                didChange = true
            }
        }

        if didChange { try repository.save() }
    }

    private func rollIncompleteOneTimeTasks(
        from previousDay: LocalDay,
        to day: LocalDay,
        templatesByID: [UUID: TaskTemplate],
        existingKeys: inout Set<LogicalTaskKey>,
        now: Date
    ) throws {
        let previousTasks = try repository.dailyTasks(on: previousDay)
        for task in previousTasks where task.completedAt == nil {
            guard let template = templatesByID[task.templateID], template.kind == .once else {
                continue
            }

            let key = LogicalTaskKey(templateID: task.templateID, dayKey: day.rawValue)
            guard existingKeys.insert(key).inserted else { continue }

            repository.insert(
                DailyTask(
                    templateID: task.templateID,
                    dayKey: day.rawValue,
                    titleSnapshot: task.titleSnapshot,
                    reminderMode: task.reminderMode,
                    reminderHour: task.reminderHour,
                    reminderMinute: task.reminderMinute,
                    sortIndex: task.sortIndex,
                    rolloverOriginID: task.id,
                    originalDayKey: task.originalDayKey,
                    rolloverCount: task.rolloverCount + 1,
                    createdAt: now,
                    priority: task.priority,
                    assignee: task.assignee
                )
            )
        }
    }

    private func generateRecurringTasks(
        on day: LocalDay,
        templates: [TaskTemplate],
        calendar: Calendar,
        existingKeys: inout Set<LogicalTaskKey>,
        now: Date
    ) {
        for template in templates where template.kind == .recurring {
            guard template.recurrence?.matches(day, calendar: calendar) == true else { continue }

            let key = LogicalTaskKey(templateID: template.id, dayKey: day.rawValue)
            guard existingKeys.insert(key).inserted else { continue }

            repository.insert(
                DailyTask(
                    templateID: template.id,
                    dayKey: day.rawValue,
                    titleSnapshot: template.title,
                    reminderMode: template.reminderMode,
                    reminderHour: template.reminderHour,
                    reminderMinute: template.reminderMinute,
                    sortIndex: template.sortIndex,
                    createdAt: now,
                    priority: template.priority,
                    assignee: template.assignee
                )
            )
        }
    }
}

private struct LogicalTaskKey: Hashable {
    let templateID: UUID
    let dayKey: String

    init(templateID: UUID, dayKey: String) {
        self.templateID = templateID
        self.dayKey = dayKey
    }

    init(task: DailyTask) {
        self.init(templateID: task.templateID, dayKey: task.dayKey)
    }
}
