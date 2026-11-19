import Foundation

public enum TaskServiceError: Error, Equatable {
    case emptyTitle
    case recurrenceRequired
    case scheduledDayInPast
    case taskNotFound
    case templateNotFound
    case instanceStillHasTemplate
    case notificationSyncFailed
}

@MainActor
public final class TaskService {
    private let repository: TaskRepository
    private let notifications: NotificationScheduling
    private let calendar: Calendar

    public init(
        repository: TaskRepository,
        notifications: NotificationScheduling,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.notifications = notifications
        self.calendar = calendar
    }

    public func today(on day: LocalDay) throws -> [DailyTask] {
        try repository.dailyTasks(on: day)
    }

    public func upcoming(on day: LocalDay) throws -> [DailyTask] {
        let oneTimeIDs = Set(try repository.templates(enabledOnly: true).filter { $0.kind == .once }.map(\.id))
        return try repository.dailyTasks(from: day.adding(days: 1, calendar: calendar))
            .filter { $0.completedAt == nil && oneTimeIDs.contains($0.templateID) }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
    }

    public func cancelUpcoming(id: UUID, on day: LocalDay) async throws {
        guard let task = try repository.dailyTask(id: id),
              task.dayKey > day.rawValue,
              task.completedAt == nil,
              let template = try repository.template(id: task.templateID),
              template.kind == .once, template.isEnabled
        else {
            throw TaskServiceError.taskNotFound
        }

        let cancelledIDs = try removeFutureInstances(templateID: template.id, after: day)
        template.isEnabled = false
        try repository.save()
        await cancelNotifications(for: cancelledIDs)
    }

    public func recurringTemplates() throws -> [TaskTemplate] {
        try repository.templates(enabledOnly: false).filter { $0.kind == .recurring }
    }

    public func create(_ draft: TaskDraft, on day: LocalDay, now: Date) async throws -> DailyTask {
        let title = try validatedTitle(for: draft)
        let assignee = normalizedAssignee(draft.assignee)
        let instanceDay = try firstInstanceDay(for: draft, today: day)
        let sortIndex = try nextSortIndex(on: instanceDay)
        let template = TaskTemplate(
            title: title,
            kind: draft.kind,
            recurrence: draft.recurrence,
            reminderMode: draft.reminderMode,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute,
            sortIndex: sortIndex,
            createdAt: now,
            updatedAt: now,
            priority: draft.priority,
            assignee: assignee
        )
        let task = DailyTask(
            templateID: template.id,
            dayKey: instanceDay.rawValue,
            titleSnapshot: title,
            reminderMode: draft.reminderMode,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute,
            sortIndex: sortIndex,
            createdAt: now,
            scheduledDayKey: draft.scheduledDay?.rawValue,
            priority: draft.priority,
            assignee: assignee
        )

        repository.insert(template)
        repository.insert(task)
        try repository.save()

        try await syncNotification(for: task, now: now)
        return task
    }

    public func update(templateID: UUID, draft: TaskDraft, on day: LocalDay, now: Date) async throws {
        let title = try validatedTitle(for: draft)
        let assignee = normalizedAssignee(draft.assignee)
        let targetDay = try firstInstanceDay(for: draft, today: day)
        guard let template = try repository.template(id: templateID) else {
            throw TaskServiceError.templateNotFound
        }

        let tasks = try repository.dailyTasks(from: day).filter { $0.templateID == templateID }
        let openTasks = tasks.filter { $0.completedAt == nil }
        let completedDays = Set(tasks.filter { $0.completedAt != nil }.map(\.dayKey))
        let previousRule = template.recurrence
        let changedKind = template.kind != draft.kind
        let isEnabled = changedKind || template.isEnabled
        let start = draft.recurrence?.startDay
        let changedFutureStart = start.map { $0 > day && $0 != previousRule?.startDay } ?? false
        let keepToday = draft.kind == .recurring && !changedKind && (!changedFutureStart || !isEnabled)
        let todayTask = keepToday ? openTasks.first { $0.dayKey == day.rawValue } : nil
        let candidates = openTasks.filter { $0.id != todayTask?.id }
        let completedToday = completedDays.contains(day.rawValue)
        let preservingSkip = todayTask == nil && previousRule == draft.recurrence
            && previousRule?.matches(day, calendar: calendar) == true
        let needsNewTemplate = completedToday && template.kind == .recurring && draft.kind == .once

        let dateToSchedule: LocalDay?
        if draft.kind == .once {
            dateToSchedule = (!candidates.isEmpty || changedKind) ? targetDay : nil
        } else if !isEnabled {
            dateToSchedule = nil
        } else if todayTask != nil || completedToday || preservingSkip {
            dateToSchedule = (!candidates.isEmpty || changedFutureStart || changedKind)
                ? draft.recurrence?.firstOccurrence(onOrAfter: day.adding(days: 1, calendar: calendar), calendar: calendar)
                : nil
        } else {
            dateToSchedule = targetDay
        }

        let activeDate = dateToSchedule.flatMap { date in
            needsNewTemplate || !completedDays.contains(date.rawValue) ? date : nil
        }
        let existingTask = activeDate.flatMap { date in
            candidates.first { $0.dayKey == date.rawValue } ?? candidates.first
        }
        let activeSortIndex: Int?
        if let activeDate {
            activeSortIndex = existingTask?.dayKey == activeDate.rawValue
                ? existingTask?.sortIndex
                : try nextSortIndex(on: activeDate)
        } else {
            activeSortIndex = nil
        }

        // A completed occurrence remains actionable today. Give the new plan a
        // separate source so toggling the old occurrence cannot disable it.
        let updatedTemplate = needsNewTemplate
            ? TaskTemplate(title: title, sortIndex: template.sortIndex, createdAt: now)
            : template
        updatedTemplate.title = title
        updatedTemplate.kind = draft.kind
        updatedTemplate.recurrence = draft.recurrence
        updatedTemplate.reminderMode = draft.reminderMode
        updatedTemplate.reminderHour = draft.reminderHour
        updatedTemplate.reminderMinute = draft.reminderMinute
        updatedTemplate.priority = draft.priority
        updatedTemplate.assignee = assignee
        updatedTemplate.isEnabled = isEnabled
        updatedTemplate.updatedAt = now
        if needsNewTemplate {
            repository.insert(updatedTemplate)
            repository.remove(template)
        }

        var updatedTasks: [DailyTask] = []
        if let todayTask {
            apply(draft, titled: title, assignee: assignee, to: todayTask)
            updatedTasks.append(todayTask)
        }

        if let activeDate, let activeSortIndex {
            let task = existingTask ?? DailyTask(
                templateID: updatedTemplate.id, dayKey: activeDate.rawValue, titleSnapshot: title, createdAt: now
            )
            task.templateID = updatedTemplate.id
            task.dayKey = activeDate.rawValue
            if task.rolloverOriginID == nil {
                task.originalDayKey = activeDate.rawValue
            }
            task.sortIndex = activeSortIndex
            apply(draft, titled: title, assignee: assignee, to: task)
            if existingTask == nil { repository.insert(task) }
            updatedTasks.append(task)
        }

        let discardedTasks = candidates.filter { $0.id != existingTask?.id }
        let cancelledIDs = discardedTasks.map(\.id)
        discardedTasks.forEach { repository.remove($0) }
        if draft.kind == .once && activeDate == nil && completedDays.contains(targetDay.rawValue) {
            updatedTemplate.isEnabled = false
        }
        try repository.save()

        await cancelNotifications(for: cancelledIDs)
        for task in updatedTasks {
            try await syncNotification(for: task, now: now)
        }
    }

    public func updateInstance(id: UUID, draft: InstanceDraft, now: Date) async throws {
        let title = try validatedTitle(draft.title)
        guard let task = try repository.dailyTask(id: id) else {
            throw TaskServiceError.taskNotFound
        }
        guard try repository.template(id: task.templateID) == nil else {
            throw TaskServiceError.instanceStillHasTemplate
        }

        task.titleSnapshot = title
        task.reminderMode = draft.reminderMode
        task.reminderHour = draft.reminderHour
        task.reminderMinute = draft.reminderMinute
        task.priority = draft.priority
        task.assignee = normalizedAssignee(draft.assignee)
        try repository.save()
        try await syncNotification(for: task, now: now)
    }

    public func setCompleted(id: UUID, completed: Bool, at date: Date) async throws {
        guard let task = try repository.dailyTask(id: id) else {
            throw TaskServiceError.taskNotFound
        }
        let template = try repository.template(id: task.templateID)

        task.completedAt = completed ? date : nil
        if template?.kind == .once {
            template?.isEnabled = !completed
            template?.updatedAt = date
        }
        try repository.save()

        if completed {
            await notifications.cancel(taskID: task.id)
        } else {
            try await syncNotification(for: task, now: date)
        }
    }

    public func setTemplateEnabled(id: UUID, enabled: Bool, on day: LocalDay, now: Date) async throws {
        guard let template = try repository.template(id: id) else {
            throw TaskServiceError.templateNotFound
        }

        if !enabled {
            let cancelledIDs = try removeFutureInstances(templateID: id, after: day)
            template.isEnabled = false
            try repository.save()
            await cancelNotifications(for: cancelledIDs)
            return
        }

        guard !template.isEnabled else { return }
        let tomorrow = day.adding(days: 1, calendar: calendar)
        let nextTask: DailyTask?
        if template.kind == .recurring,
           let nextDay = template.recurrence?.firstOccurrence(onOrAfter: tomorrow, calendar: calendar) {
            let existing = try repository.dailyTasks(on: nextDay).first { $0.templateID == id }
            if let existing {
                nextTask = existing
            } else {
                let newTask = DailyTask(
                    templateID: id,
                    dayKey: nextDay.rawValue,
                    titleSnapshot: template.title,
                    reminderMode: template.reminderMode,
                    reminderHour: template.reminderHour,
                    reminderMinute: template.reminderMinute,
                    sortIndex: template.sortIndex,
                    createdAt: now,
                    priority: template.priority,
                    assignee: template.assignee
                )
                repository.insert(newTask)
                nextTask = newTask
            }
        } else {
            nextTask = nil
        }

        template.isEnabled = true
        try repository.save()
        if let nextTask { try await syncNotification(for: nextTask, now: now) }
    }

    public func reorderTemplates(ids: [UUID]) throws {
        var templates: [TaskTemplate] = []
        for id in ids {
            guard let template = try repository.template(id: id) else {
                throw TaskServiceError.templateNotFound
            }
            templates.append(template)
        }

        for (index, template) in templates.enumerated() {
            template.sortIndex = index * 1_000
        }
        try repository.save()
    }

    public func deleteTemplate(id: UUID, on day: LocalDay) async throws {
        guard let template = try repository.template(id: id) else {
            throw TaskServiceError.templateNotFound
        }

        let cancelledIDs = try removeFutureInstances(templateID: id, after: day)
        repository.remove(template)
        try repository.save()
        await cancelNotifications(for: cancelledIDs)
    }

    public func reorder(ids: [UUID]) throws {
        var tasks: [DailyTask] = []
        for id in ids {
            guard let task = try repository.dailyTask(id: id) else {
                throw TaskServiceError.taskNotFound
            }
            tasks.append(task)
        }

        for (index, task) in tasks.enumerated() {
            task.sortIndex = index * 1_000
        }
        try repository.save()
    }

    public func delete(id: UUID, scope: DeleteScope) async throws {
        guard let task = try repository.dailyTask(id: id) else {
            throw TaskServiceError.taskNotFound
        }

        switch scope {
        case .todayOnly:
            if let template = try repository.template(id: task.templateID), template.kind == .once {
                template.isEnabled = false
            }
            repository.remove(task)
            try repository.save()
            await notifications.cancel(taskID: task.id)
        case .allFuture:
            guard let template = try repository.template(id: task.templateID) else {
                throw TaskServiceError.templateNotFound
            }
            let cancelledIDs = try removeFutureInstances(
                templateID: template.id, after: LocalDay(rawValue: task.dayKey)
            ) + [task.id]
            repository.remove(task)
            template.isEnabled = false
            try repository.save()
            await cancelNotifications(for: cancelledIDs)
        }
    }

    private func validatedTitle(for draft: TaskDraft) throws -> String {
        let title = try validatedTitle(draft.title)
        guard draft.kind != .recurring || draft.recurrence != nil else {
            throw TaskServiceError.recurrenceRequired
        }
        return title
    }

    private func validatedTitle(_ proposedTitle: String) throws -> String {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw TaskServiceError.emptyTitle
        }
        return title
    }

    private func normalizedAssignee(_ proposedAssignee: String?) -> String? {
        guard let name = proposedAssignee?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    private func nextSortIndex(on day: LocalDay) throws -> Int {
        let currentMax = try repository.dailyTasks(on: day).map(\.sortIndex).max()
        return (currentMax ?? -1_000) + 1_000
    }

    private func firstInstanceDay(for draft: TaskDraft, today: LocalDay) throws -> LocalDay {
        if draft.kind == .once {
            let scheduledDay = draft.scheduledDay ?? today
            guard scheduledDay >= today else { throw TaskServiceError.scheduledDayInPast }
            return scheduledDay
        }

        guard let nextDay = draft.recurrence?.firstOccurrence(onOrAfter: today, calendar: calendar) else {
            throw TaskServiceError.recurrenceRequired
        }
        return nextDay
    }

    private func apply(_ draft: TaskDraft, titled title: String, assignee: String?, to task: DailyTask) {
        task.titleSnapshot = title
        task.scheduledDayKey = draft.scheduledDay?.rawValue
        task.reminderMode = draft.reminderMode
        task.reminderHour = draft.reminderHour
        task.reminderMinute = draft.reminderMinute
        task.priority = draft.priority
        task.assignee = assignee
    }

    private func removeFutureInstances(templateID: UUID, after day: LocalDay) throws -> [UUID] {
        let tasks = try repository.dailyTasks(from: day.adding(days: 1, calendar: calendar)).filter {
            $0.templateID == templateID && $0.completedAt == nil
        }
        let ids = tasks.map(\.id)
        tasks.forEach { repository.remove($0) }
        return ids
    }

    private func cancelNotifications(for ids: [UUID]) async {
        for id in ids {
            await notifications.cancel(taskID: id)
        }
    }

    private func syncNotification(for task: DailyTask, now: Date) async throws {
        do {
            let settings = try repository.settings()
            try await notifications.sync(
                task: task,
                persistentIntervalMinutes: settings.persistentIntervalMinutes,
                now: now
            )
        } catch {
            throw TaskServiceError.notificationSyncFailed
        }
    }
}
