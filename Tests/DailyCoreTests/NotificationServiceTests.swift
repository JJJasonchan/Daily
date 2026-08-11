import Foundation
import UserNotifications
import XCTest
@testable import DailyCore

@MainActor
final class NotificationServiceTests: XCTestCase {
    private let calendar = NotificationServiceTests.utcCalendar

    func testNoneClearsExistingTaskRequestsWithoutAddingOne() async throws {
        let task = makeTask(reminderMode: .none)
        let stale = request(id: NotificationID.task(task.id, sequence: 4))
        let unrelated = request(id: "unrelated")
        let center = RecordingNotificationCenter(pending: [stale, unrelated])
        let service = NotificationService(center: center, calendar: calendar)

        try await service.sync(task: task, persistentIntervalMinutes: 15, now: date(2026, 8, 12, 9, 0))

        XCTAssertEqual(center.addedRequests.count, 0)
        XCTAssertEqual(center.removedIDs, [stale.identifier])
        XCTAssertEqual(center.pending.map(\.identifier), [unrelated.identifier])
    }

    func testOnceSchedulesOneFutureSameDayCalendarRequest() async throws {
        let task = makeTask(reminderMode: .once, hour: 10, minute: 30)
        let center = RecordingNotificationCenter()
        let service = NotificationService(center: center, calendar: calendar)

        try await service.sync(task: task, persistentIntervalMinutes: 15, now: date(2026, 8, 12, 10, 0))

        let added = try XCTUnwrap(center.addedRequests.first)
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(added.identifier, NotificationID.task(task.id, sequence: 0))
        XCTAssertEqual(added.content.title, "Read")
        XCTAssertEqual(added.content.categoryIdentifier, "TASK_REMINDER")
        XCTAssertNotNil(added.content.sound)
        let trigger = try XCTUnwrap(added.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertEqual(trigger.dateComponents.month, 8)
        XCTAssertEqual(trigger.dateComponents.day, 12)
        XCTAssertEqual(trigger.dateComponents.hour, 10)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
    }

    func testOnceDoesNotSchedulePastOrDifferentDayTime() async throws {
        let past = makeTask(reminderMode: .once, hour: 9, minute: 59)
        let tomorrow = makeTask(dayKey: "2026-08-13", reminderMode: .once, hour: 10, minute: 30)
        let center = RecordingNotificationCenter()
        let service = NotificationService(center: center, calendar: calendar)
        let now = date(2026, 8, 12, 10, 0)

        try await service.sync(task: past, persistentIntervalMinutes: 15, now: now)
        try await service.sync(task: tomorrow, persistentIntervalMinutes: 15, now: now)

        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testPersistentPastNominalTimeStartsAtNowPlusIntervalAndCreatesEightRequests() async throws {
        let task = makeTask(reminderMode: .persistent, hour: 8, minute: 0)
        let center = RecordingNotificationCenter()
        let service = NotificationService(center: center, calendar: calendar)

        try await service.sync(task: task, persistentIntervalMinutes: 15, now: date(2026, 8, 12, 9, 0))

        XCTAssertEqual(center.addedRequests.map(\.identifier), (0..<8).map { NotificationID.task(task.id, sequence: $0) })
        let intervals = try center.addedRequests.map {
            try XCTUnwrap($0.trigger as? UNTimeIntervalNotificationTrigger).timeInterval
        }
        XCTAssertEqual(intervals, [900, 1_800, 2_700, 3_600, 4_500, 5_400, 6_300, 7_200])
    }

    func testPersistentFutureNominalTimeUsesCalendarFirstThenIntervalFollowUps() async throws {
        let task = makeTask(reminderMode: .persistent, hour: 10, minute: 30)
        let center = RecordingNotificationCenter()
        let service = NotificationService(center: center, calendar: calendar)

        try await service.sync(task: task, persistentIntervalMinutes: 15, now: date(2026, 8, 12, 10, 0))

        XCTAssertEqual(center.addedRequests.count, 8)
        XCTAssertTrue(center.addedRequests[0].trigger is UNCalendarNotificationTrigger)
        let intervals = try center.addedRequests.dropFirst().map {
            try XCTUnwrap($0.trigger as? UNTimeIntervalNotificationTrigger).timeInterval
        }
        XCTAssertEqual(intervals, [2_700, 3_600, 4_500, 5_400, 6_300, 7_200, 8_100])
    }

    func testCancelRemovesEveryPendingIdentifierWithTaskPrefixOnly() async {
        let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let matching = [request(id: NotificationID.task(taskID, sequence: 0)), request(id: NotificationID.task(taskID, sequence: 7))]
        let other = request(id: NotificationID.task(UUID(), sequence: 0))
        let center = RecordingNotificationCenter(pending: matching + [other])
        let service = NotificationService(center: center, calendar: calendar)

        await service.cancel(taskID: taskID)

        XCTAssertEqual(Set(center.removedIDs), Set(matching.map(\.identifier)))
        XCTAssertEqual(center.pending.map(\.identifier), [other.identifier])
    }

    func testDailyReminderUsesStableIdentifierAndDisablingRemovesIt() async throws {
        let center = RecordingNotificationCenter()
        let service = NotificationService(center: center, calendar: calendar)
        let enabled = AppSettings(dailyReminderEnabled: true, dailyReminderHour: 8, dailyReminderMinute: 45)

        try await service.syncDailyReminder(settings: enabled, now: date(2026, 8, 12, 7, 0))

        let added = try XCTUnwrap(center.addedRequests.last)
        XCTAssertEqual(added.identifier, "daily.summary")
        XCTAssertEqual(added.content.body, "查看今天的任务并开始行动。")
        let trigger = try XCTUnwrap(added.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertEqual(trigger.dateComponents.minute, 45)

        let disabled = AppSettings(dailyReminderEnabled: false, dailyReminderHour: 8, dailyReminderMinute: 45)
        try await service.syncDailyReminder(settings: disabled, now: date(2026, 8, 12, 7, 1))

        XCTAssertEqual(center.removedIDs.filter { $0 == NotificationID.daily }.count, 2)
        XCTAssertFalse(center.pending.contains { $0.identifier == NotificationID.daily })
    }

    func testRebuildRemovesStaleTaskRequestsAndSchedulesOnlyIncompleteTasks() async throws {
        let incomplete = makeTask(reminderMode: .once, hour: 10, minute: 30)
        let completed = makeTask(reminderMode: .once, hour: 10, minute: 45, completedAt: date(2026, 8, 12, 9, 0))
        let stale = request(id: "task.11111111-2222-3333-4444-555555555555.3")
        let unrelated = request(id: "other.pending")
        let center = RecordingNotificationCenter(pending: [stale, unrelated])
        let service = NotificationService(center: center, calendar: calendar)

        try await service.rebuild(
            tasks: [completed, incomplete],
            settings: AppSettings(persistentIntervalMinutes: 15),
            now: date(2026, 8, 12, 10, 0)
        )

        XCTAssertTrue(center.removedIDs.contains(stale.identifier))
        XCTAssertEqual(center.addedRequests.map(\.identifier), [NotificationID.task(incomplete.id, sequence: 0)])
        XCTAssertTrue(center.pending.contains { $0.identifier == unrelated.identifier })
        XCTAssertEqual(center.requestAuthorizationCallCount, 0)
    }

    func testAuthorizationIsRequestedOnlyThroughExplicitAction() async throws {
        let center = RecordingNotificationCenter(authorizationResult: true)
        let service = NotificationService(center: center, calendar: calendar)
        let task = makeTask(reminderMode: .once, hour: 10, minute: 30)

        try await service.sync(task: task, persistentIntervalMinutes: 15, now: date(2026, 8, 12, 10, 0))
        XCTAssertEqual(center.requestAuthorizationCallCount, 0)

        let granted = try await service.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(center.requestAuthorizationCallCount, 1)
    }

    func testSettingsRejectUnsupportedPersistentIntervals() throws {
        let repository = TestTaskRepository()
        let notifications = SettingsNotificationScheduler(repository: repository)
        let service = ReminderSettingsService(repository: repository, notifications: notifications)

        for interval in [0, 4, 6, 20, 61] {
            XCTAssertThrowsError(try service.updatePersistentInterval(minutes: interval)) { error in
                XCTAssertEqual(error as? ReminderSettingsError, .invalidInterval)
            }
        }
        XCTAssertEqual(repository.saveCallCount, 0)
    }

    func testSettingsAcceptOnlySupportedPersistentIntervals() throws {
        let repository = TestTaskRepository()
        let notifications = SettingsNotificationScheduler(repository: repository)
        let service = ReminderSettingsService(repository: repository, notifications: notifications)

        for interval in [5, 10, 15, 30, 60] {
            try service.updatePersistentInterval(minutes: interval)
            XCTAssertEqual(repository.storedSettings.persistentIntervalMinutes, interval)
        }
        XCTAssertEqual(repository.saveCallCount, 5)
    }

    func testEnabledDailyReminderRejectsMissingOrOutOfRangeTime() async {
        let repository = TestTaskRepository()
        let notifications = SettingsNotificationScheduler(repository: repository)
        let service = ReminderSettingsService(repository: repository, notifications: notifications)

        for (hour, minute) in [(nil, 30), (8, nil), (-1, 30), (24, 30), (8, -1), (8, 60)] {
            do {
                try await service.updateDailyReminder(enabled: true, hour: hour, minute: minute, now: date(2026, 8, 12, 7, 0))
                XCTFail("Expected invalid time for \(String(describing: hour)):\(String(describing: minute))")
            } catch {
                XCTAssertEqual(error as? ReminderSettingsError, .invalidTime)
            }
        }
        XCTAssertEqual(repository.saveCallCount, 0)
        XCTAssertEqual(notifications.dailySyncCallCount, 0)
    }

    func testDailyReminderSavesBeforeSynchronizingNotification() async throws {
        let repository = TestTaskRepository()
        let notifications = SettingsNotificationScheduler(repository: repository)
        let service = ReminderSettingsService(repository: repository, notifications: notifications)
        let now = date(2026, 8, 12, 7, 0)

        try await service.updateDailyReminder(enabled: true, hour: 8, minute: 30, now: now)

        XCTAssertTrue(repository.storedSettings.dailyReminderEnabled)
        XCTAssertEqual(repository.storedSettings.dailyReminderHour, 8)
        XCTAssertEqual(repository.storedSettings.dailyReminderMinute, 30)
        XCTAssertEqual(repository.saveCallCount, 1)
        XCTAssertEqual(notifications.saveCountsAtDailySync, [1])
        XCTAssertEqual(notifications.dailySyncCallCount, 1)
    }

    func testDailyReminderMapsNotificationFailureAfterSave() async {
        let repository = TestTaskRepository()
        let notifications = SettingsNotificationScheduler(repository: repository)
        notifications.shouldFailDailySync = true
        let service = ReminderSettingsService(repository: repository, notifications: notifications)

        do {
            try await service.updateDailyReminder(enabled: false, hour: nil, minute: nil, now: date(2026, 8, 12, 7, 0))
            XCTFail("Expected notification sync failure")
        } catch {
            XCTAssertEqual(error as? ReminderSettingsError, .notificationSyncFailed)
        }
        XCTAssertEqual(repository.saveCallCount, 1)
    }

    private func makeTask(
        dayKey: String = "2026-08-12",
        reminderMode: ReminderMode,
        hour: Int? = nil,
        minute: Int? = nil,
        completedAt: Date? = nil
    ) -> DailyTask {
        DailyTask(
            templateID: UUID(),
            dayKey: dayKey,
            titleSnapshot: "Read",
            reminderMode: reminderMode,
            reminderHour: hour,
            reminderMinute: minute,
            completedAt: completedAt
        )
    }

    private func request(id: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
private final class RecordingNotificationCenter: NotificationCenterClient {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIDs: [String] = []
    private(set) var requestAuthorizationCallCount = 0
    private let authorizationResult: Bool
    var pending: [UNNotificationRequest]

    init(pending: [UNNotificationRequest] = [], authorizationResult: Bool = false) {
        self.pending = pending
        self.authorizationResult = authorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        return authorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePending(ids: [String]) {
        removedIDs.append(contentsOf: ids)
        pending.removeAll { ids.contains($0.identifier) }
    }

    func pendingRequests() async -> [UNNotificationRequest] { pending }
}

@MainActor
private final class SettingsNotificationScheduler: NotificationScheduling {
    enum Failure: Error { case sync }

    private let repository: TestTaskRepository
    private(set) var dailySyncCallCount = 0
    private(set) var saveCountsAtDailySync: [Int] = []
    var shouldFailDailySync = false

    init(repository: TestTaskRepository) {
        self.repository = repository
    }

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {}
    func cancel(taskID: UUID) async {}

    func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        dailySyncCallCount += 1
        saveCountsAtDailySync.append(repository.saveCallCount)
        if shouldFailDailySync { throw Failure.sync }
    }

    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {}
}
