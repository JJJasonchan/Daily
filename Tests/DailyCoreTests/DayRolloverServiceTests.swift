import XCTest
@testable import DailyCore

@MainActor
final class DayRolloverServiceTests: XCTestCase {
    func testProcessingTwiceDoesNotDuplicateTemplateAndDayInstance() async throws {
        let template = recurringTemplate(startDay: "2026-08-11")
        let repository = TestTaskRepository(
            templates: [template],
            settings: AppSettings(lastProcessedDayKey: "2026-08-11")
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()
        try await service.processThroughToday()

        let matchingTasks = repository.storedTasks.filter {
            $0.templateID == template.id && $0.dayKey == "2026-08-12"
        }
        XCTAssertEqual(matchingTasks.count, 1)
    }

    func testIncompleteOneTimeTaskBuildsDailyRolloverChainWithOnlyTodayIncomplete() async throws {
        let template = TaskTemplate(title: "Submit expenses", kind: .once)
        let original = DailyTask(
            templateID: template.id,
            dayKey: "2026-08-09",
            titleSnapshot: template.title,
            originalDayKey: "2026-08-09"
        )
        let repository = TestTaskRepository(
            templates: [template],
            tasks: [original],
            settings: AppSettings(lastProcessedDayKey: "2026-08-09")
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        let chain = repository.storedTasks.sorted { $0.dayKey < $1.dayKey }
        XCTAssertEqual(chain.map(\.dayKey), ["2026-08-09", "2026-08-10", "2026-08-11", "2026-08-12"])
        XCTAssertEqual(chain.map(\.rolloverCount), [0, 1, 2, 3])
        XCTAssertEqual(chain.map(\.originalDayKey), Array(repeating: "2026-08-09", count: 4))
        guard chain.count == 4 else { return }
        XCTAssertNil(chain[0].rolloverOriginID)
        XCTAssertEqual(chain[1].rolloverOriginID, chain[0].id)
        XCTAssertEqual(chain[2].rolloverOriginID, chain[1].id)
        XCTAssertEqual(chain[3].rolloverOriginID, chain[2].id)
        XCTAssertEqual(
            chain.map { service.historyStatus(for: $0, allTasks: chain) },
            [.rolledOver, .rolledOver, .rolledOver, .incomplete]
        )
    }

    func testIncompleteRecurringTaskCreatesFreshMatchingInstanceWithoutRollover() async throws {
        let template = recurringTemplate(startDay: "2026-08-11")
        let prior = DailyTask(
            templateID: template.id,
            dayKey: "2026-08-11",
            titleSnapshot: template.title
        )
        let repository = TestTaskRepository(
            templates: [template],
            tasks: [prior],
            settings: AppSettings(lastProcessedDayKey: "2026-08-11")
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        let today = try XCTUnwrap(repository.storedTasks.first { $0.dayKey == "2026-08-12" })
        XCTAssertNil(today.rolloverOriginID)
        XCTAssertEqual(today.originalDayKey, "2026-08-12")
        XCTAssertEqual(today.rolloverCount, 0)
        XCTAssertEqual(service.historyStatus(for: prior, allTasks: repository.storedTasks), .incomplete)
    }

    func testDisabledTemplateDoesNotGenerateFutureInstance() async throws {
        let disabled = recurringTemplate(startDay: "2026-08-11", isEnabled: false)
        let enabled = recurringTemplate(startDay: "2026-08-11")
        let repository = TestTaskRepository(
            templates: [disabled, enabled],
            settings: AppSettings(lastProcessedDayKey: "2026-08-11")
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        XCTAssertEqual(repository.storedTasks.map(\.templateID), [enabled.id])
    }

    func testSelectedWeekdayRuleSkipsNonmatchingDays() async throws {
        let template = TaskTemplate(
            title: "Wednesday review",
            kind: .recurring,
            recurrence: RecurrenceRule(
                frequency: .selectedWeekdays,
                weekdays: [4],
                startDay: LocalDay(rawValue: "2026-08-10")
            )
        )
        let repository = TestTaskRepository(
            templates: [template],
            settings: AppSettings(lastProcessedDayKey: "2026-08-09")
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        XCTAssertEqual(repository.storedTasks.map(\.dayKey), ["2026-08-12"])
    }

    func testSuccessfulProcessingPersistsEachDayAndAdvancesLastProcessedDayToToday() async throws {
        let settings = AppSettings(lastProcessedDayKey: "2026-08-09")
        let repository = TestTaskRepository(settings: settings)
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        XCTAssertEqual(settings.lastProcessedDayKey, "2026-08-12")
        XCTAssertEqual(repository.saveCallCount, 3)
    }

    func testRebuildRunsOnceWithOnlyTodaysIncompleteTasks() async throws {
        let incomplete = DailyTask(templateID: UUID(), dayKey: "2026-08-12", titleSnapshot: "Open")
        let completed = DailyTask(
            templateID: UUID(),
            dayKey: "2026-08-12",
            titleSnapshot: "Done",
            completedAt: Date(timeIntervalSince1970: 1)
        )
        let old = DailyTask(templateID: UUID(), dayKey: "2026-08-11", titleSnapshot: "Old")
        let repository = TestTaskRepository(
            tasks: [incomplete, completed, old],
            settings: AppSettings(lastProcessedDayKey: "2026-08-12")
        )
        let notifications = RolloverNotificationScheduler()
        let service = makeService(
            repository: repository,
            notifications: notifications,
            today: "2026-08-12"
        )

        try await service.processThroughToday()

        XCTAssertEqual(notifications.rebuildTaskIDs, [[incomplete.id]])
    }

    func testFirstRunGeneratesOnlyTodaysMatchingRecurringInstance() async throws {
        let template = recurringTemplate(startDay: "2026-08-01")
        let oneTimeTemplate = TaskTemplate(title: "Unknown history", kind: .once)
        let priorOneTimeTask = DailyTask(
            templateID: oneTimeTemplate.id,
            dayKey: "2026-08-11",
            titleSnapshot: oneTimeTemplate.title
        )
        let settings = AppSettings()
        let repository = TestTaskRepository(
            templates: [template, oneTimeTemplate],
            tasks: [priorOneTimeTask],
            settings: settings
        )
        let service = makeService(repository: repository, today: "2026-08-12")

        try await service.processThroughToday()

        XCTAssertEqual(repository.storedTasks.map(\.dayKey).sorted(), ["2026-08-11", "2026-08-12"])
        XCTAssertEqual(repository.storedTasks.filter { $0.dayKey == "2026-08-12" }.map(\.templateID), [template.id])
        XCTAssertEqual(settings.lastProcessedDayKey, "2026-08-12")
        XCTAssertEqual(repository.saveCallCount, 1)
    }

    func testCompletedStatusTakesPrecedenceOverRolloverStatus() {
        let completionDate = Date(timeIntervalSince1970: 1)
        let completed = DailyTask(
            templateID: UUID(),
            dayKey: "2026-08-11",
            titleSnapshot: "Done",
            completedAt: completionDate
        )
        let child = DailyTask(
            templateID: completed.templateID,
            dayKey: "2026-08-12",
            titleSnapshot: "Child",
            rolloverOriginID: completed.id
        )
        let service = makeService(repository: TestTaskRepository(), today: "2026-08-12")

        XCTAssertEqual(service.historyStatus(for: completed, allTasks: [completed, child]), .completed)
    }

    private func recurringTemplate(startDay: String, isEnabled: Bool = true) -> TaskTemplate {
        TaskTemplate(
            title: "Read",
            kind: .recurring,
            recurrence: RecurrenceRule(
                frequency: .daily,
                weekdays: [],
                startDay: LocalDay(rawValue: startDay)
            ),
            isEnabled: isEnabled
        )
    }

    private func makeService(
        repository: TestTaskRepository,
        notifications: RolloverNotificationScheduler = RolloverNotificationScheduler(),
        today: String
    ) -> DayRolloverService {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = LocalDay(rawValue: today)
        let provider = FixedDayProvider(now: day.date(in: calendar), calendar: calendar)
        return DayRolloverService(
            repository: repository,
            notifications: notifications,
            dayProvider: provider
        )
    }
}

private struct FixedDayProvider: DayProviding {
    let now: Date
    let calendar: Calendar
}

@MainActor
private final class RolloverNotificationScheduler: NotificationScheduling {
    private(set) var rebuildTaskIDs: [[UUID]] = []

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {}

    func cancel(taskID: UUID) async {}

    func syncDailyReminder(settings: AppSettings, now: Date) async throws {}

    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        rebuildTaskIDs.append(tasks.map(\.id))
    }
}
