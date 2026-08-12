import Foundation
import UserNotifications
import Sparkle
import XCTest
@testable import DailyApp
@testable import DailyCore

@MainActor
final class HistoryPresentationTests: XCTestCase {
    private let day = LocalDay(rawValue: "2026-08-12")

    func testHistorySummaryCountsCompletedIncompleteAndRolledOverInstances() throws {
        let completion = Date(timeIntervalSince1970: 1_786_521_600)
        let completedOne = DailyTask(
            templateID: UUID(),
            dayKey: day.rawValue,
            titleSnapshot: "完成一",
            sortIndex: 0,
            completedAt: completion
        )
        let completedTwo = DailyTask(
            templateID: UUID(),
            dayKey: day.rawValue,
            titleSnapshot: "完成二",
            sortIndex: 1_000,
            completedAt: completion
        )
        let incompleteRecurring = DailyTask(
            templateID: UUID(),
            dayKey: day.rawValue,
            titleSnapshot: "未完成重复任务",
            sortIndex: 2_000
        )
        let rolledOverOneTime = DailyTask(
            templateID: UUID(),
            dayKey: day.rawValue,
            titleSnapshot: "已顺延一次性任务",
            sortIndex: 3_000
        )
        let rolloverChild = DailyTask(
            templateID: rolledOverOneTime.templateID,
            dayKey: "2026-08-13",
            titleSnapshot: rolledOverOneTime.titleSnapshot,
            rolloverOriginID: rolledOverOneTime.id
        )
        let model = makeModel(
            tasks: [
                completedOne,
                completedTwo,
                incompleteRecurring,
                rolledOverOneTime,
                rolloverChild
            ]
        )

        let summaries = try model.history(weekContaining: day)
        let summary = try XCTUnwrap(summaries.first { $0.day == day })

        XCTAssertEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(summary.completionFraction, 0.5)
        XCTAssertEqual(
            summary.tasks.map(\.1),
            [.completed, .completed, .incomplete, .rolledOver]
        )
    }

    func testEmptyHistoryDayHasNoCompletionFraction() throws {
        let model = makeModel(tasks: [])

        let summaries = try model.history(weekContaining: day)
        let summary = try XCTUnwrap(summaries.first { $0.day == day })

        XCTAssertEqual(summary.totalCount, 0)
        XCTAssertEqual(summary.completedCount, 0)
        XCTAssertNil(summary.completionFraction)
    }

    private func makeModel(tasks: [DailyTask]) -> AppModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let provider = HistoryDayProvider(
            now: day.date(in: calendar),
            calendar: calendar
        )
        let repository = HistoryTaskRepository(tasks: tasks)
        let notifications = HistoryNotificationScheduler()
        return AppModel(
            taskService: TaskService(
                repository: repository,
                notifications: notifications
            ),
            rolloverService: DayRolloverService(
                repository: repository,
                notifications: notifications,
                dayProvider: provider
            ),
            reminderSettingsService: ReminderSettingsService(
                repository: repository,
                notifications: notifications
            ),
            repository: repository,
            dayProvider: provider,
            notificationService: NotificationService(
                center: HistoryNotificationCenterClient(),
                calendar: calendar
            ),
            lifecycleObserver: HistoryLifecycleObserver(),
            updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        )
    }
}

private struct HistoryDayProvider: DayProviding {
    let now: Date
    let calendar: Calendar
}

@MainActor
private final class HistoryTaskRepository: TaskRepository {
    private var storedTasks: [DailyTask]
    private let storedSettings = AppSettings(lastProcessedDayKey: "2026-08-12")

    init(tasks: [DailyTask]) {
        storedTasks = tasks
    }

    func templates(enabledOnly: Bool) throws -> [TaskTemplate] { [] }
    func template(id: UUID) throws -> TaskTemplate? { nil }

    func dailyTasks(on day: LocalDay) throws -> [DailyTask] {
        storedTasks
            .filter { $0.dayKey == day.rawValue }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask] {
        storedTasks
            .filter { start.rawValue <= $0.dayKey && $0.dayKey <= end.rawValue }
            .sorted {
                ($0.dayKey, $0.sortIndex) < ($1.dayKey, $1.sortIndex)
            }
    }

    func dailyTask(id: UUID) throws -> DailyTask? {
        storedTasks.first { $0.id == id }
    }

    func insert(_ template: TaskTemplate) {}
    func insert(_ task: DailyTask) { storedTasks.append(task) }
    func remove(_ template: TaskTemplate) {}
    func remove(_ task: DailyTask) { storedTasks.removeAll { $0.id == task.id } }
    func settings() throws -> AppSettings { storedSettings }
    func save() throws {}
}

@MainActor
private final class HistoryNotificationScheduler: NotificationScheduling {
    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {}
    func cancel(taskID: UUID) async {}
    func syncDailyReminder(settings: AppSettings, now: Date) async throws {}
    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {}
}

@MainActor
private final class HistoryNotificationCenterClient: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> Bool { false }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePending(ids: [String]) {}
    func pendingRequests() async -> [UNNotificationRequest] { [] }
}

@MainActor
private final class HistoryLifecycleObserver: AppLifecycleObserving {
    func start(handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?) {}
    func stop() {}
}
