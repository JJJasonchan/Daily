import Foundation

public enum TaskServiceError: Error, Equatable {
    case emptyTitle
    case recurrenceRequired
    case taskNotFound
    case templateNotFound
    case notificationSyncFailed
}

@MainActor
public final class TaskService {
    private let repository: TaskRepository
    private let notifications: NotificationScheduling

    public init(repository: TaskRepository, notifications: NotificationScheduling) {
        self.repository = repository
        self.notifications = notifications
    }

    public func today(on day: LocalDay) throws -> [DailyTask] {
        try repository.dailyTasks(on: day)
    }

    public func recurringTemplates() throws -> [TaskTemplate] {
        try repository.templates(enabledOnly: false).filter { $0.kind == .recurring }
    }

    public func create(_ draft: TaskDraft, on day: LocalDay, now: Date) async throws -> DailyTask {
        let title = try validatedTitle(for: draft)
        let sortIndex = try nextSortIndex(on: day)
        let template = TaskTemplate(
            title: title,
            kind: draft.kind,
            recurrence: draft.recurrence,
            reminderMode: draft.reminderMode,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute,
            sortIndex: sortIndex,
            createdAt: now,
            updatedAt: now
        )
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: title,
            reminderMode: draft.reminderMode,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute,
            sortIndex: sortIndex,
            createdAt: now
        )

        repository.insert(template)
        repository.insert(task)
        try repository.save()

        try await syncNotification(for: task, now: now)
        return task
    }

    public func update(templateID: UUID, draft: TaskDraft, on day: LocalDay, now: Date) async throws {
        let title = try validatedTitle(for: draft)
        guard let template = try repository.template(id: templateID) else {
            throw TaskServiceError.templateNotFound
        }

        let recurrence: RecurrenceRule?
        if template.kind == .recurring,
           draft.kind == .recurring,
           var updatedRecurrence = draft.recurrence,
           let originalStartDay = template.recurrence?.startDay {
            updatedRecurrence.startDay = originalStartDay
            recurrence = updatedRecurrence
        } else {
            recurrence = draft.recurrence
        }

        template.title = title
        template.kind = draft.kind
        template.recurrence = recurrence
        template.reminderMode = draft.reminderMode
        template.reminderHour = draft.reminderHour
        template.reminderMinute = draft.reminderMinute
        template.updatedAt = now

        let updatedTasks = try repository.dailyTasks(on: day).filter {
            $0.templateID == templateID && $0.completedAt == nil
        }
        for task in updatedTasks {
            task.titleSnapshot = title
            task.reminderMode = draft.reminderMode
            task.reminderHour = draft.reminderHour
            task.reminderMinute = draft.reminderMinute
        }
        try repository.save()

        for task in updatedTasks {
            try await syncNotification(for: task, now: now)
        }
    }

    public func updateInstance(id: UUID, draft: InstanceDraft, now: Date) async throws {
        let title = try validatedTitle(draft.title)
        guard let task = try repository.dailyTask(id: id) else {
            throw TaskServiceError.taskNotFound
        }

        task.titleSnapshot = title
        task.reminderMode = draft.reminderMode
        task.reminderHour = draft.reminderHour
        task.reminderMinute = draft.reminderMinute
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

    public func setTemplateEnabled(id: UUID, enabled: Bool) throws {
        guard let template = try repository.template(id: id) else {
            throw TaskServiceError.templateNotFound
        }

        template.isEnabled = enabled
        try repository.save()
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

    public func deleteTemplate(id: UUID) throws {
        guard let template = try repository.template(id: id) else {
            throw TaskServiceError.templateNotFound
        }
        repository.remove(template)
        try repository.save()
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
            repository.remove(task)
            try repository.save()
            await notifications.cancel(taskID: task.id)
        case .allFuture:
            guard let template = try repository.template(id: task.templateID) else {
                throw TaskServiceError.templateNotFound
            }
            repository.remove(task)
            template.isEnabled = false
            try repository.save()
            await notifications.cancel(taskID: task.id)
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

    private func nextSortIndex(on day: LocalDay) throws -> Int {
        let currentMax = try repository.dailyTasks(on: day).map(\.sortIndex).max()
        return (currentMax ?? -1_000) + 1_000
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
