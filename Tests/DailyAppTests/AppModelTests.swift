import AppKit
import Foundation
import UserNotifications
import XCTest
@testable import DailyApp
@testable import DailyCore

@MainActor
final class AppModelTests: XCTestCase {
    private let day = LocalDay(rawValue: "2026-08-12")
    private let now = Date(timeIntervalSince1970: 1_786_521_600)

    func testMotionSpecsKeepInteractionSemanticsInspectable() {
        XCTAssertEqual(MotionTokens.pressScale, 0.97)
        XCTAssertEqual(MotionTokens.standard.duration, 0.36)
        XCTAssertEqual(MotionTokens.standard.bounce, 0)
        XCTAssertEqual(MotionTokens.physical.bounce, 0.18)
        XCTAssertEqual(MotionTokens.reduced.pressScale, 1)
        XCTAssertEqual(MotionTokens.reduced.hoverLift, 0)
    }

    func testReorderProjectionClampsDestinationAndMovesNeighborsContinuously() {
        XCTAssertEqual(
            ReorderLayout.destinationIndex(
                startIndex: 0,
                translation: 99,
                rowStride: 66,
                count: 4
            ),
            2
        )
        XCTAssertEqual(
            ReorderLayout.destinationIndex(
                startIndex: 3,
                translation: 200,
                rowStride: 66,
                count: 4
            ),
            3
        )
        XCTAssertEqual(
            ReorderLayout.neighborOffset(
                itemIndex: 1,
                startIndex: 0,
                translation: 99,
                rowStride: 66
            ),
            -66
        )
        XCTAssertEqual(
            ReorderLayout.neighborOffset(
                itemIndex: 2,
                startIndex: 0,
                translation: 99,
                rowStride: 66
            ),
            -33
        )
    }

    func testEmptyTaskListHasZeroCompletionFraction() throws {
        let fixture = makeFixture()

        try fixture.model.reload()

        XCTAssertEqual(fixture.model.completedCount, 0)
        XCTAssertEqual(fixture.model.completionFraction, 0)
    }

    func testTwoCompletedTasksOutOfFourHaveHalfCompletion() throws {
        let tasks = (0..<4).map { index in
            DailyTask(
                templateID: UUID(),
                dayKey: day.rawValue,
                titleSnapshot: "Task \(index)",
                completedAt: index < 2 ? now : nil
            )
        }
        let fixture = makeFixture(tasks: tasks)

        try fixture.model.reload()

        XCTAssertEqual(fixture.model.completedCount, 2)
        XCTAssertEqual(fixture.model.completionFraction, 0.5)
    }

    func testAddReloadsTodayState() async {
        let fixture = makeFixture()

        await fixture.model.add(TaskDraft(title: "Write report"))

        XCTAssertEqual(fixture.model.todayTasks.map(\.titleSnapshot), ["Write report"])
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testUpdateRoutesTaskEditorChangesThroughModelAndReloadsToday() async throws {
        let template = TaskTemplate(title: "Old title")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()

        await fixture.model.update(task, with: TaskDraft(title: "New title"))

        XCTAssertEqual(fixture.model.todayTasks.map(\.titleSnapshot), ["New title"])
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testToggleReloadsTaskAndCompletedCount() async throws {
        let template = TaskTemplate(title: "Walk")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()

        await fixture.model.toggle(task)

        XCTAssertNotNil(fixture.model.todayTasks.first?.completedAt)
        XCTAssertEqual(fixture.model.completedCount, 1)
        XCTAssertEqual(fixture.model.lastCompletionUndo?.taskID, task.id)
        XCTAssertEqual(fixture.model.lastCompletionUndo?.wasCompleted, false)
    }

    func testUndoRestoresCompletionStateThatExistedBeforeToggle() async throws {
        let template = TaskTemplate(title: "Walk", isEnabled: false)
        let originalCompletion = now.addingTimeInterval(-300)
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title,
            completedAt: originalCompletion
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()

        await fixture.model.toggle(task)
        XCTAssertNil(fixture.model.todayTasks.first?.completedAt)

        await fixture.model.undoLastCompletion()

        XCTAssertNotNil(fixture.model.todayTasks.first?.completedAt)
        XCTAssertEqual(fixture.model.completedCount, 1)
        XCTAssertNil(fixture.model.lastCompletionUndo)
    }

    func testFailedAddPreservesCurrentListAndShowsSpecificError() async throws {
        let existing = DailyTask(
            templateID: UUID(),
            dayKey: day.rawValue,
            titleSnapshot: "Existing"
        )
        let fixture = makeFixture(tasks: [existing])
        try fixture.model.reload()
        let existingIDs = fixture.model.todayTasks.map(\.id)

        await fixture.model.add(TaskDraft(title: "   "))

        XCTAssertEqual(fixture.model.todayTasks.map(\.id), existingIDs)
        XCTAssertEqual(fixture.model.errorMessage, "任务标题不能为空。")
    }

    func testNotificationFailureExplainsTaskWasSaved() async throws {
        let fixture = makeFixture()
        fixture.notifications.shouldFailSync = true

        await fixture.model.add(
            TaskDraft(
                title: "Water plants",
                reminderMode: .once,
                reminderHour: 9,
                reminderMinute: 0
            )
        )

        XCTAssertEqual(fixture.model.todayTasks.map(\.titleSnapshot), ["Water plants"])
        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["Water plants"])
        XCTAssertEqual(fixture.model.errorMessage, "任务已保存，但提醒失败。请重试。")
    }

    func testToggleNotificationFailureReloadsSavedStateAndReplacesPreviousUndo() async throws {
        let previousTemplate = TaskTemplate(title: "Previous")
        let currentTemplate = TaskTemplate(title: "Current", isEnabled: false)
        let previousTask = DailyTask(
            templateID: previousTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: previousTemplate.title
        )
        let currentTask = DailyTask(
            templateID: currentTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: currentTemplate.title,
            completedAt: now.addingTimeInterval(-60)
        )
        let fixture = makeFixture(
            templates: [previousTemplate, currentTemplate],
            tasks: [previousTask, currentTask]
        )
        try fixture.model.reload()
        await fixture.model.toggle(previousTask)
        let readsBeforePartialSuccess = fixture.repository.dailyTasksCallCount
        fixture.notifications.shouldFailSync = true

        await fixture.model.toggle(currentTask)

        XCTAssertEqual(fixture.repository.dailyTasksCallCount, readsBeforePartialSuccess + 1)
        XCTAssertNil(fixture.model.todayTasks.first { $0.id == currentTask.id }?.completedAt)
        XCTAssertEqual(fixture.model.lastCompletionUndo?.taskID, currentTask.id)
        XCTAssertEqual(fixture.model.lastCompletionUndo?.wasCompleted, true)
        XCTAssertEqual(fixture.model.errorMessage, "任务状态已更新，但提醒失败。请重试。")
    }

    func testCreateSuccessFollowedByReloadFailureDoesNotClaimCreateFailedOrWriteTwice() async {
        let fixture = makeFixture()
        fixture.repository.failReadsAfterNextSave = true

        await fixture.model.add(TaskDraft(title: "Saved once"))

        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["Saved once"])
        XCTAssertEqual(fixture.repository.saveCallCount, 1)
        XCTAssertTrue(fixture.model.todayTasks.isEmpty)
        XCTAssertEqual(fixture.model.errorMessage, "任务已保存，但列表刷新失败。请重试。")
    }

    func testTwoConsumersOfOneModelObserveTheSameArray() async {
        let fixture = makeFixture()
        let window = ModelConsumer(model: fixture.model)
        let menuBar = ModelConsumer(model: fixture.model)

        await window.model.add(TaskDraft(title: "Shared task"))

        XCTAssertEqual(window.model.todayTasks.map(\.id), menuBar.model.todayTasks.map(\.id))
        XCTAssertEqual(menuBar.model.todayTasks.map(\.titleSnapshot), ["Shared task"])
    }

    func testStartProcessesRolloverBeforeReloadingState() async {
        let recurrence = RecurrenceRule(frequency: .daily, weekdays: [], startDay: day)
        let template = TaskTemplate(title: "Read", kind: .recurring, recurrence: recurrence)
        let fixture = makeFixture(templates: [template], lastProcessedDay: "2026-08-11")

        await fixture.model.start()

        XCTAssertEqual(fixture.model.todayTasks.map(\.templateID), [template.id])
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testRepeatedStartRegistersLifecycleObserversOnlyOnceAndCleanupIsExplicit() async {
        let fixture = makeFixture()

        await fixture.model.start()
        await fixture.model.start()

        XCTAssertEqual(fixture.lifecycle.startCallCount, 1)

        fixture.model.stopObservingLifecycle()

        XCTAssertEqual(fixture.lifecycle.stopCallCount, 1)
    }

    func testLifecycleEventProcessesRolloverThenReloads() async {
        let recurrence = RecurrenceRule(frequency: .daily, weekdays: [], startDay: day)
        let template = TaskTemplate(title: "Read", kind: .recurring, recurrence: recurrence)
        let fixture = makeFixture(templates: [template], lastProcessedDay: "2026-08-11")
        await fixture.model.start()
        fixture.repository.storedTasks.removeAll()
        fixture.repository.storedSettings.lastProcessedDayKey = "2026-08-11"

        await fixture.lifecycle.sendEvent()

        XCTAssertEqual(fixture.model.todayTasks.map(\.templateID), [template.id])
    }

    func testStoppedModelIgnoresLifecycleCallbackAlreadyQueuedBeforeStop() async {
        let fixture = makeFixture()
        await fixture.model.start()
        let queuedCallback = fixture.lifecycle.capturedHandler()
        let rebuildsBeforeStop = fixture.notifications.rebuildCallCount

        fixture.model.stopObservingLifecycle()
        if let queuedTask = queuedCallback?() {
            await queuedTask.value
        }

        XCTAssertEqual(fixture.lifecycle.startCallCount, 1)
        XCTAssertEqual(fixture.notifications.rebuildCallCount, rebuildsBeforeStop)
    }

    func testOverlappingLifecycleEventsAreSerializedCoalescedAndCommitLatestState() async {
        let oldTask = DailyTask(templateID: UUID(), dayKey: day.rawValue, titleSnapshot: "Old")
        let latestTask = DailyTask(templateID: UUID(), dayKey: day.rawValue, titleSnapshot: "Latest")
        let fixture = makeFixture(tasks: [oldTask])
        fixture.notifications.blockNextRebuild()
        let initialRefresh = Task { await fixture.model.start() }
        await fixture.notifications.waitUntilRebuildIsBlocked()

        let firstEvent = Task { await fixture.lifecycle.sendEvent() }
        let secondEvent = Task { await fixture.lifecycle.sendEvent() }
        for _ in 0..<5 { await Task.yield() }
        fixture.repository.storedTasks = [latestTask]
        fixture.notifications.resumeBlockedRebuild()
        await initialRefresh.value
        await firstEvent.value
        await secondEvent.value

        XCTAssertEqual(fixture.notifications.maximumConcurrentRebuildCount, 1)
        XCTAssertEqual(fixture.notifications.rebuildCallCount, 2)
        XCTAssertEqual(fixture.model.todayTasks.map(\.id), [latestTask.id])
    }

    func testReloadFailureDoesNotReplacePreviouslyLoadedArrays() throws {
        let task = DailyTask(templateID: UUID(), dayKey: day.rawValue, titleSnapshot: "Keep")
        let fixture = makeFixture(tasks: [task])
        try fixture.model.reload()
        fixture.repository.shouldFailReads = true

        XCTAssertThrowsError(try fixture.model.reload())
        XCTAssertEqual(fixture.model.todayTasks.map(\.id), [task.id])
    }

    func testSystemObserverForwardsEveryLifecycleSignalOnceAndStopsCleanly() async {
        let defaultCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = SystemAppLifecycleObserver(
            notificationCenter: defaultCenter,
            workspaceNotificationCenter: workspaceCenter
        )
        var receivedCount = 0
        observer.start {
            receivedCount += 1
            return nil
        }
        observer.start {
            receivedCount += 100
            return nil
        }

        defaultCenter.post(name: .NSCalendarDayChanged, object: nil)
        defaultCenter.post(name: .NSSystemClockDidChange, object: nil)
        defaultCenter.post(name: .NSSystemTimeZoneDidChange, object: nil)
        defaultCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(receivedCount, 5)

        observer.stop()
        defaultCenter.post(name: .NSCalendarDayChanged, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(receivedCount, 5)
    }

    private func makeFixture(
        templates: [TaskTemplate] = [],
        tasks: [DailyTask] = [],
        lastProcessedDay: String? = "2026-08-12"
    ) -> AppModelFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let provider = AppModelFixedDayProvider(now: now, calendar: calendar)
        let repository = AppModelTestRepository(
            templates: templates,
            tasks: tasks,
            settings: AppSettings(lastProcessedDayKey: lastProcessedDay)
        )
        let notifications = AppModelNotificationScheduler()
        let taskService = TaskService(repository: repository, notifications: notifications)
        let rolloverService = DayRolloverService(
            repository: repository,
            notifications: notifications,
            dayProvider: provider
        )
        let reminderSettingsService = ReminderSettingsService(
            repository: repository,
            notifications: notifications
        )
        let notificationService = NotificationService(center: AppModelNotificationCenterClient())
        let lifecycle = ManualAppLifecycleObserver()
        let model = AppModel(
            taskService: taskService,
            rolloverService: rolloverService,
            reminderSettingsService: reminderSettingsService,
            repository: repository,
            dayProvider: provider,
            notificationService: notificationService,
            lifecycleObserver: lifecycle
        )
        return AppModelFixture(
            model: model,
            repository: repository,
            notifications: notifications,
            lifecycle: lifecycle
        )
    }
}

@MainActor
private struct AppModelFixture {
    let model: AppModel
    let repository: AppModelTestRepository
    let notifications: AppModelNotificationScheduler
    let lifecycle: ManualAppLifecycleObserver
}

@MainActor
private struct ModelConsumer {
    let model: AppModel
}

private struct AppModelFixedDayProvider: DayProviding {
    let now: Date
    let calendar: Calendar
}

@MainActor
private final class AppModelTestRepository: TaskRepository {
    enum Failure: Error { case read }

    var storedTemplates: [TaskTemplate]
    var storedTasks: [DailyTask]
    let storedSettings: AppSettings
    var shouldFailReads = false
    var failReadsAfterNextSave = false
    private(set) var dailyTasksCallCount = 0
    private(set) var saveCallCount = 0

    init(templates: [TaskTemplate], tasks: [DailyTask], settings: AppSettings) {
        storedTemplates = templates
        storedTasks = tasks
        storedSettings = settings
    }

    func templates(enabledOnly: Bool) throws -> [TaskTemplate] {
        if shouldFailReads { throw Failure.read }
        return storedTemplates
            .filter { !enabledOnly || $0.isEnabled }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func template(id: UUID) throws -> TaskTemplate? {
        if shouldFailReads { throw Failure.read }
        return storedTemplates.first { $0.id == id }
    }

    func dailyTasks(on day: LocalDay) throws -> [DailyTask] {
        dailyTasksCallCount += 1
        if shouldFailReads { throw Failure.read }
        return storedTasks
            .filter { $0.dayKey == day.rawValue }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask] {
        if shouldFailReads { throw Failure.read }
        return storedTasks.filter { start.rawValue <= $0.dayKey && $0.dayKey <= end.rawValue }
    }

    func dailyTask(id: UUID) throws -> DailyTask? {
        if shouldFailReads { throw Failure.read }
        return storedTasks.first { $0.id == id }
    }

    func insert(_ template: TaskTemplate) { storedTemplates.append(template) }
    func insert(_ task: DailyTask) { storedTasks.append(task) }
    func remove(_ task: DailyTask) { storedTasks.removeAll { $0.id == task.id } }
    func settings() throws -> AppSettings { storedSettings }
    func save() throws {
        saveCallCount += 1
        if failReadsAfterNextSave {
            failReadsAfterNextSave = false
            shouldFailReads = true
        }
    }
}

@MainActor
private final class AppModelNotificationScheduler: NotificationScheduling {
    enum Failure: Error { case sync }
    var shouldFailSync = false
    private(set) var rebuildCallCount = 0
    private(set) var maximumConcurrentRebuildCount = 0
    private var activeRebuildCount = 0
    private var shouldBlockNextRebuild = false
    private var blockedRebuildContinuation: CheckedContinuation<Void, Never>?
    private var blockedStartWaiter: CheckedContinuation<Void, Never>?
    private var hasBlockedRebuild = false

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {
        if shouldFailSync { throw Failure.sync }
    }

    func cancel(taskID: UUID) async {}

    func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        if shouldFailSync { throw Failure.sync }
    }

    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        rebuildCallCount += 1
        activeRebuildCount += 1
        maximumConcurrentRebuildCount = max(maximumConcurrentRebuildCount, activeRebuildCount)
        defer { activeRebuildCount -= 1 }
        if shouldBlockNextRebuild {
            shouldBlockNextRebuild = false
            hasBlockedRebuild = true
            blockedStartWaiter?.resume()
            blockedStartWaiter = nil
            await withCheckedContinuation { continuation in
                blockedRebuildContinuation = continuation
            }
        }
        if shouldFailSync { throw Failure.sync }
    }

    func blockNextRebuild() {
        shouldBlockNextRebuild = true
    }

    func waitUntilRebuildIsBlocked() async {
        if hasBlockedRebuild { return }
        await withCheckedContinuation { continuation in
            blockedStartWaiter = continuation
        }
    }

    func resumeBlockedRebuild() {
        blockedRebuildContinuation?.resume()
        blockedRebuildContinuation = nil
    }
}

@MainActor
private final class AppModelNotificationCenterClient: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePending(ids: [String]) {}
    func pendingRequests() async -> [UNNotificationRequest] { [] }
}

@MainActor
private final class ManualAppLifecycleObserver: AppLifecycleObserving {
    private var handler: (@MainActor @Sendable () -> Task<Void, Never>?)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(
        handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?
    ) {
        startCallCount += 1
        self.handler = handler
    }

    func stop() {
        stopCallCount += 1
        handler = nil
    }

    func sendEvent() async {
        if let task = handler?() {
            await task.value
        }
    }

    func capturedHandler() -> (@MainActor @Sendable () -> Task<Void, Never>?)? {
        handler
    }
}
