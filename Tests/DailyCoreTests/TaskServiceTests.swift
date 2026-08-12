import XCTest
@testable import DailyCore

@MainActor
final class TaskServiceTests: XCTestCase {
    private let day = LocalDay(rawValue: "2026-08-12")
    private let now = Date(timeIntervalSince1970: 1_786_521_600)

    func testCreateRejectsBlankTitleWithoutInserting() async throws {
        let repository = TestTaskRepository()
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        do {
            _ = try await service.create(TaskDraft(title: " \n "), on: day, now: now)
            XCTFail("Expected an empty title error")
        } catch let error as TaskServiceError {
            XCTAssertEqual(error, .emptyTitle)
        }

        XCTAssertTrue(repository.storedTemplates.isEmpty)
        XCTAssertTrue(repository.storedTasks.isEmpty)
    }

    func testCreateTrimsTitleCreatesCurrentInstanceAndUsesStoredReminderInterval() async throws {
        let repository = TestTaskRepository(settings: AppSettings(persistentIntervalMinutes: 23))
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(repository: repository, notifications: notifications)

        let created = try await service.create(
            TaskDraft(title: "  Plan day  ", reminderMode: .persistent, reminderHour: 9, reminderMinute: 30),
            on: day,
            now: now
        )

        XCTAssertEqual(repository.storedTemplates.count, 1)
        XCTAssertEqual(repository.storedTasks.count, 1)
        XCTAssertEqual(created.dayKey, "2026-08-12")
        XCTAssertEqual(created.titleSnapshot, "Plan day")
        XCTAssertEqual(created.reminderMode, .persistent)
        XCTAssertEqual(created.reminderHour, 9)
        XCTAssertEqual(created.reminderMinute, 30)
        XCTAssertEqual(created.sortIndex, 0)
        XCTAssertEqual(repository.storedTemplates[0].title, "Plan day")
        XCTAssertEqual(repository.storedTemplates[0].sortIndex, 0)
        XCTAssertEqual(notifications.syncedTaskIDs, [created.id])
        XCTAssertEqual(notifications.persistentIntervals, [23])
    }

    func testCreateRequiresRecurrenceForRecurringTemplate() async throws {
        let repository = TestTaskRepository()
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        do {
            _ = try await service.create(TaskDraft(title: "Exercise", kind: .recurring), on: day, now: now)
            XCTFail("Expected a recurrence error")
        } catch let error as TaskServiceError {
            XCTAssertEqual(error, .recurrenceRequired)
        }

        XCTAssertTrue(repository.storedTemplates.isEmpty)
    }

    func testRecurringTemplatesIncludesEnabledAndDisabledRecurringButExcludesOneTime() throws {
        let enabled = recurringTemplate(title: "Enabled")
        enabled.sortIndex = 0
        let disabled = recurringTemplate(title: "Disabled")
        disabled.sortIndex = 1_000
        disabled.isEnabled = false
        let oneTime = TaskTemplate(title: "Once", kind: .once, sortIndex: 2_000)
        let repository = TestTaskRepository(templates: [oneTime, disabled, enabled])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        let templates = try service.recurringTemplates()

        XCTAssertEqual(templates.map(\.id), [enabled.id, disabled.id])
    }

    func testDisabledRecurringTemplateRemainsQueryableAndCanBeReenabled() throws {
        let template = recurringTemplate(title: "Exercise")
        let repository = TestTaskRepository(templates: [template])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        try service.setTemplateEnabled(id: template.id, enabled: false)

        XCTAssertEqual(try service.recurringTemplates().map(\.id), [template.id])
        XCTAssertFalse(template.isEnabled)

        try service.setTemplateEnabled(id: template.id, enabled: true)

        XCTAssertEqual(try service.recurringTemplates().map(\.id), [template.id])
        XCTAssertTrue(template.isEnabled)
    }

    func testRecurringTemplateReorderAssignsSparseIndexesWithoutChangingDailyTasks() throws {
        let first = recurringTemplate(title: "First")
        first.sortIndex = 100
        let second = recurringTemplate(title: "Second")
        second.sortIndex = 200
        let historicalTask = DailyTask(
            templateID: first.id,
            dayKey: "2026-08-11",
            titleSnapshot: first.title,
            sortIndex: 700
        )
        let repository = TestTaskRepository(
            templates: [first, second],
            tasks: [historicalTask]
        )
        let service = TaskService(
            repository: repository,
            notifications: RecordingNotificationScheduler()
        )

        try service.reorderTemplates(ids: [second.id, first.id])

        XCTAssertEqual(second.sortIndex, 0)
        XCTAssertEqual(first.sortIndex, 1_000)
        XCTAssertEqual(historicalTask.sortIndex, 700)
    }

    func testDeleteRecurringTemplateKeepsEveryDailyTaskInstance() throws {
        let template = recurringTemplate(title: "Read")
        let historicalTask = DailyTask(
            templateID: template.id,
            dayKey: "2026-08-11",
            titleSnapshot: template.title
        )
        let todayTask = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let repository = TestTaskRepository(
            templates: [template],
            tasks: [historicalTask, todayTask]
        )
        let service = TaskService(
            repository: repository,
            notifications: RecordingNotificationScheduler()
        )

        try service.deleteTemplate(id: template.id)

        XCTAssertTrue(repository.storedTemplates.isEmpty)
        XCTAssertEqual(repository.storedTasks.map(\.id), [historicalTask.id, todayTask.id])
    }

    func testDailyTaskFromDeletedRecurringTemplateCanStillBeCompleted() async throws {
        let template = recurringTemplate(title: "Read")
        let todayTask = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let repository = TestTaskRepository(
            templates: [template],
            tasks: [todayTask]
        )
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(
            repository: repository,
            notifications: notifications
        )

        try service.deleteTemplate(id: template.id)
        try await service.setCompleted(id: todayTask.id, completed: true, at: now)

        XCTAssertEqual(todayTask.completedAt, now)
        XCTAssertEqual(notifications.cancelledTaskIDs, [todayTask.id])
    }

    func testUpdateOrphanTaskChangesOnlyThatInstanceSnapshotAndDoesNotRestoreTemplate() async throws {
        let templateID = UUID()
        let historicalTask = DailyTask(
            templateID: templateID,
            dayKey: "2026-08-11",
            titleSnapshot: "Historical title",
            reminderMode: .once,
            reminderHour: 8,
            reminderMinute: 0
        )
        let todayTask = DailyTask(
            templateID: templateID,
            dayKey: day.rawValue,
            titleSnapshot: "Today title"
        )
        let repository = TestTaskRepository(tasks: [historicalTask, todayTask])
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(repository: repository, notifications: notifications)

        try await service.updateInstance(
            id: todayTask.id,
            draft: InstanceDraft(
                title: "  Edited today  ",
                reminderMode: .persistent,
                reminderHour: 10,
                reminderMinute: 20
            ),
            now: now
        )

        XCTAssertTrue(repository.storedTemplates.isEmpty)
        XCTAssertEqual(todayTask.titleSnapshot, "Edited today")
        XCTAssertEqual(todayTask.reminderMode, .persistent)
        XCTAssertEqual(todayTask.reminderHour, 10)
        XCTAssertEqual(todayTask.reminderMinute, 20)
        XCTAssertEqual(historicalTask.titleSnapshot, "Historical title")
        XCTAssertEqual(historicalTask.reminderMode, .once)
        XCTAssertEqual(notifications.syncedTaskIDs, [todayTask.id])
    }

    func testUpdatingRecurringTemplatePreservesOriginalRecurrenceStartDay() async throws {
        let originalStart = LocalDay(rawValue: "2026-07-01")
        let template = TaskTemplate(
            title: "Read",
            kind: .recurring,
            recurrence: RecurrenceRule(
                frequency: .daily,
                weekdays: [],
                startDay: originalStart
            )
        )
        let repository = TestTaskRepository(templates: [template])
        let service = TaskService(
            repository: repository,
            notifications: RecordingNotificationScheduler()
        )

        try await service.update(
            templateID: template.id,
            draft: TaskDraft(
                title: "Read weekdays",
                kind: .recurring,
                recurrence: RecurrenceRule(
                    frequency: .weekdays,
                    weekdays: [],
                    startDay: LocalDay(rawValue: "2026-08-12")
                )
            ),
            on: day,
            now: now
        )

        XCTAssertEqual(template.recurrence?.frequency, .weekdays)
        XCTAssertEqual(template.recurrence?.startDay, originalStart)
    }

    func testUpdateChangesTemplateAndTodaysIncompleteSnapshot() async throws {
        let template = recurringTemplate(title: "Old", reminderMode: .once, hour: 8, minute: 0)
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: "Old",
            reminderMode: .once,
            reminderHour: 8,
            reminderMinute: 0
        )
        let repository = TestTaskRepository(templates: [template], tasks: [task])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())
        let newRule = RecurrenceRule(frequency: .weekdays, weekdays: [], startDay: day)

        try await service.update(
            templateID: template.id,
            draft: TaskDraft(title: "  New  ", kind: .recurring, recurrence: newRule, reminderMode: .persistent, reminderHour: 10, reminderMinute: 15),
            on: day,
            now: now
        )

        XCTAssertEqual(template.title, "New")
        XCTAssertEqual(template.recurrence, newRule)
        XCTAssertEqual(template.reminderMode, .persistent)
        XCTAssertEqual(template.reminderHour, 10)
        XCTAssertEqual(template.reminderMinute, 15)
        XCTAssertEqual(task.titleSnapshot, "New")
        XCTAssertEqual(task.reminderMode, .persistent)
        XCTAssertEqual(task.reminderHour, 10)
        XCTAssertEqual(task.reminderMinute, 15)
    }

    func testUpdatePreservesTodaysCompletedSnapshot() async throws {
        let template = recurringTemplate(title: "Old")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: "Old",
            completedAt: now
        )
        let repository = TestTaskRepository(templates: [template], tasks: [task])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        try await service.update(
            templateID: template.id,
            draft: TaskDraft(title: "New", kind: .recurring, recurrence: template.recurrence),
            on: day,
            now: now
        )

        XCTAssertEqual(template.title, "New")
        XCTAssertEqual(task.titleSnapshot, "Old")
    }

    func testCompletingOneTimeTaskRecordsCompletionDisablesTemplateAndCancelsReminder() async throws {
        let template = TaskTemplate(title: "Pay bill", kind: .once)
        let task = DailyTask(templateID: template.id, dayKey: day.rawValue, titleSnapshot: "Pay bill")
        let repository = TestTaskRepository(templates: [template], tasks: [task])
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(repository: repository, notifications: notifications)

        try await service.setCompleted(id: task.id, completed: true, at: now)

        XCTAssertEqual(task.completedAt, now)
        XCTAssertFalse(template.isEnabled)
        XCTAssertEqual(notifications.cancelledTaskIDs, [task.id])
    }

    func testUncompletingOneTimeTaskClearsCompletionReenablesTemplateAndReschedules() async throws {
        let template = TaskTemplate(title: "Pay bill", kind: .once, isEnabled: false)
        let task = DailyTask(templateID: template.id, dayKey: day.rawValue, titleSnapshot: "Pay bill", completedAt: now)
        let repository = TestTaskRepository(templates: [template], tasks: [task], settings: AppSettings(persistentIntervalMinutes: 31))
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(repository: repository, notifications: notifications)

        try await service.setCompleted(id: task.id, completed: false, at: now)

        XCTAssertNil(task.completedAt)
        XCTAssertTrue(template.isEnabled)
        XCTAssertEqual(notifications.syncedTaskIDs, [task.id])
        XCTAssertEqual(notifications.persistentIntervals, [31])
    }

    func testReorderAssignsSparseIndexesInProvidedOrder() throws {
        let templateID = UUID()
        let first = DailyTask(templateID: templateID, dayKey: day.rawValue, titleSnapshot: "First", sortIndex: 100)
        let second = DailyTask(templateID: templateID, dayKey: day.rawValue, titleSnapshot: "Second", sortIndex: 200)
        let third = DailyTask(templateID: templateID, dayKey: day.rawValue, titleSnapshot: "Third", sortIndex: 300)
        let repository = TestTaskRepository(tasks: [first, second, third])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        try service.reorder(ids: [third.id, first.id, second.id])

        XCTAssertEqual(third.sortIndex, 0)
        XCTAssertEqual(first.sortIndex, 1_000)
        XCTAssertEqual(second.sortIndex, 2_000)
    }

    func testDeleteTodayOnlyRemovesInstanceAndKeepsTemplate() async throws {
        let template = recurringTemplate(title: "Read")
        let task = DailyTask(templateID: template.id, dayKey: day.rawValue, titleSnapshot: "Read")
        let repository = TestTaskRepository(templates: [template], tasks: [task])
        let service = TaskService(repository: repository, notifications: RecordingNotificationScheduler())

        try await service.delete(id: task.id, scope: .todayOnly)

        XCTAssertTrue(repository.storedTasks.isEmpty)
        XCTAssertEqual(repository.storedTemplates.map(\.id), [template.id])
        XCTAssertTrue(template.isEnabled)
    }

    func testDeleteAllFutureRemovesInstanceDisablesTemplateAndCancelsReminder() async throws {
        let template = recurringTemplate(title: "Read")
        let task = DailyTask(templateID: template.id, dayKey: day.rawValue, titleSnapshot: "Read")
        let repository = TestTaskRepository(templates: [template], tasks: [task])
        let notifications = RecordingNotificationScheduler()
        let service = TaskService(repository: repository, notifications: notifications)

        try await service.delete(id: task.id, scope: .allFuture)

        XCTAssertTrue(repository.storedTasks.isEmpty)
        XCTAssertFalse(template.isEnabled)
        XCTAssertEqual(notifications.cancelledTaskIDs, [task.id])
    }

    func testCreateKeepsSavedTaskWhenNotificationSyncFails() async throws {
        let repository = TestTaskRepository()
        let notifications = RecordingNotificationScheduler()
        notifications.shouldFailSync = true
        let service = TaskService(repository: repository, notifications: notifications)

        do {
            _ = try await service.create(TaskDraft(title: "Retry me"), on: day, now: now)
            XCTFail("Expected a notification sync error")
        } catch let error as TaskServiceError {
            XCTAssertEqual(error, .notificationSyncFailed)
        }

        XCTAssertEqual(repository.storedTemplates.count, 1)
        XCTAssertEqual(repository.storedTasks.count, 1)
        XCTAssertEqual(repository.saveCallCount, 1)
    }

    private func recurringTemplate(
        title: String,
        reminderMode: ReminderMode = .none,
        hour: Int? = nil,
        minute: Int? = nil
    ) -> TaskTemplate {
        TaskTemplate(
            title: title,
            kind: .recurring,
            recurrence: RecurrenceRule(frequency: .daily, weekdays: [], startDay: day),
            reminderMode: reminderMode,
            reminderHour: hour,
            reminderMinute: minute
        )
    }
}
