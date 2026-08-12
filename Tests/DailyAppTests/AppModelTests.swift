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

    func testCompletedRowsCannotEditUntilCompletionIsCancelled() {
        XCTAssertFalse(TaskRowState.canEdit(isCompleted: true))
        XCTAssertTrue(TaskRowState.canEdit(isCompleted: false))
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

    func testTemplateActionsReloadRulesAndKeepHistoricalInstances() throws {
        let first = recurringTemplate(title: "First", sortIndex: 0)
        let second = recurringTemplate(title: "Second", sortIndex: 1_000)
        let historicalTask = DailyTask(
            templateID: first.id,
            dayKey: "2026-08-11",
            titleSnapshot: first.title
        )
        let fixture = makeFixture(
            templates: [first, second],
            tasks: [historicalTask]
        )
        try fixture.model.reload()

        XCTAssertEqual(fixture.model.setTemplateEnabled(first, enabled: false), .success)
        XCTAssertFalse(first.isEnabled)

        fixture.model.reorderTemplates(ids: [second.id, first.id])
        XCTAssertEqual(fixture.model.templates.map(\.id), [second.id, first.id])

        XCTAssertEqual(fixture.model.deleteTemplate(first), .success)
        XCTAssertEqual(fixture.model.templates.map(\.id), [second.id])
        XCTAssertEqual(fixture.repository.storedTasks.map(\.id), [historicalTask.id])
    }

    func testTemplateEditorActionUsesExistingTaskEditorSavePath() async throws {
        let template = recurringTemplate(title: "Old", sortIndex: 0)
        let todayTask = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let fixture = makeFixture(templates: [template], tasks: [todayTask])
        try fixture.model.reload()
        let recurrence = RecurrenceRule(
            frequency: .weekdays,
            weekdays: [],
            startDay: day
        )

        let result = await fixture.model.update(
            template,
            with: TaskDraft(
                title: "New",
                kind: .recurring,
                recurrence: recurrence
            )
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(template.title, "New")
        XCTAssertEqual(template.recurrence, recurrence)
        XCTAssertEqual(fixture.model.todayTasks.first?.titleSnapshot, "New")
    }

    func testLoadingSettingsReadsPersistedValuesAndActualDeniedPermission() async {
        let settings = AppSettings(
            dailyReminderEnabled: true,
            dailyReminderHour: 8,
            dailyReminderMinute: 30,
            persistentIntervalMinutes: 10,
            lastProcessedDayKey: day.rawValue
        )
        let authorization = AppModelNotificationCenterClient(status: .denied)
        let fixture = makeFixture(
            settings: settings,
            authorizationClient: authorization
        )

        await fixture.model.loadReminderSettings()

        XCTAssertTrue(fixture.model.dailyReminderEnabled)
        XCTAssertEqual(fixture.model.dailyReminderHour, 8)
        XCTAssertEqual(fixture.model.dailyReminderMinute, 30)
        XCTAssertEqual(fixture.model.persistentIntervalMinutes, 10)
        XCTAssertEqual(fixture.model.notificationAuthorizationStatus, .denied)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testNotificationAuthorizationIsRequestedOnlyByExplicitAction() async {
        let authorization = AppModelNotificationCenterClient(
            status: .notDetermined,
            grantsAuthorization: true
        )
        let fixture = makeFixture(authorizationClient: authorization)

        await fixture.model.loadReminderSettings()
        XCTAssertEqual(authorization.requestCallCount, 0)

        await fixture.model.requestNotificationAuthorization()

        XCTAssertEqual(authorization.requestCallCount, 1)
        XCTAssertEqual(fixture.model.notificationAuthorizationStatus, .authorized)
    }

    func testSavingReminderSettingsPersistsEveryFieldAndSchedulesDailyReminder() async {
        let settings = AppSettings(lastProcessedDayKey: day.rawValue)
        let fixture = makeFixture(settings: settings)

        let result = await fixture.model.saveReminderSettings(
            enabled: true,
            hour: 9,
            minute: 45,
            persistentIntervalMinutes: 30
        )

        XCTAssertEqual(result, .success)
        XCTAssertTrue(settings.dailyReminderEnabled)
        XCTAssertEqual(settings.dailyReminderHour, 9)
        XCTAssertEqual(settings.dailyReminderMinute, 45)
        XCTAssertEqual(settings.persistentIntervalMinutes, 30)
        XCTAssertEqual(fixture.notifications.dailyReminderSyncCallCount, 1)
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testReminderSchedulingFailureReportsPersistedPartialSuccessAccurately() async {
        let settings = AppSettings(lastProcessedDayKey: day.rawValue)
        let fixture = makeFixture(settings: settings)
        fixture.notifications.shouldFailSync = true

        let result = await fixture.model.saveReminderSettings(
            enabled: true,
            hour: 9,
            minute: 45,
            persistentIntervalMinutes: 60
        )

        XCTAssertEqual(result, .partialSuccess)
        XCTAssertTrue(settings.dailyReminderEnabled)
        XCTAssertEqual(settings.persistentIntervalMinutes, 60)
        XCTAssertEqual(
            fixture.model.errorMessage,
            "设置已保存，但每日提醒安排失败。请检查通知权限后重试。"
        )
    }

    func testAddReloadsTodayState() async {
        let fixture = makeFixture()

        let result = await fixture.model.add(TaskDraft(title: "Write report"))

        XCTAssertEqual(result, .success)
        XCTAssertEqual(fixture.model.todayTasks.map(\.titleSnapshot), ["Write report"])
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testAddReminderPartialSuccessIsDismissableAndWritesOnlyOnce() async {
        let fixture = makeFixture()
        fixture.notifications.shouldFailSync = true

        let result = await fixture.model.add(
            TaskDraft(
                title: "Water plants",
                reminderMode: .once,
                reminderHour: 9,
                reminderMinute: 0
            )
        )

        XCTAssertEqual(result, .partialSuccess)
        XCTAssertTrue(result.shouldDismissEditor)
        XCTAssertEqual(fixture.repository.saveCallCount, 1)
        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["Water plants"])
    }

    func testAddSettingsReadFailureAfterSaveIsDismissableAndWritesOnlyOnce() async {
        let fixture = makeFixture()
        fixture.repository.shouldFailSettings = true

        let result = await fixture.model.add(
            TaskDraft(
                title: "Water plants",
                reminderMode: .once,
                reminderHour: 9,
                reminderMinute: 0
            )
        )

        XCTAssertEqual(result, .partialSuccess)
        XCTAssertTrue(result.shouldDismissEditor)
        XCTAssertEqual(fixture.repository.saveCallCount, 1)
        XCTAssertEqual(fixture.repository.storedTemplates.count, 1)
        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["Water plants"])
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

    func testUpdateReminderPartialSuccessIsDismissableAndWritesOnlyOnce() async throws {
        let template = TaskTemplate(title: "Old title")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()
        fixture.notifications.shouldFailSync = true

        let result = await fixture.model.update(
            task,
            with: TaskDraft(
                title: "New title",
                reminderMode: .once,
                reminderHour: 10,
                reminderMinute: 30
            )
        )

        XCTAssertEqual(result, .partialSuccess)
        XCTAssertTrue(result.shouldDismissEditor)
        XCTAssertEqual(fixture.repository.saveCallCount, 1)
        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["New title"])
    }

    func testUpdateSettingsReadFailureAfterSaveIsDismissableAndWritesOnlyOnce() async throws {
        let template = TaskTemplate(title: "Old title")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()
        fixture.repository.shouldFailSettings = true

        let result = await fixture.model.update(
            task,
            with: TaskDraft(
                title: "New title",
                reminderMode: .once,
                reminderHour: 10,
                reminderMinute: 30
            )
        )

        XCTAssertEqual(result, .partialSuccess)
        XCTAssertTrue(result.shouldDismissEditor)
        XCTAssertEqual(fixture.repository.saveCallCount, 1)
        XCTAssertEqual(fixture.repository.storedTemplates.count, 1)
        XCTAssertEqual(fixture.repository.storedTasks.map(\.titleSnapshot), ["New title"])
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

        let token = await fixture.model.toggle(task)
        XCTAssertNil(fixture.model.todayTasks.first?.completedAt)

        await fixture.model.undo(token!)

        XCTAssertNotNil(fixture.model.todayTasks.first?.completedAt)
        XCTAssertEqual(fixture.model.completedCount, 1)
        XCTAssertNil(fixture.model.lastCompletionUndo)
    }

    func testStaleUndoTokenDoesNotClearOrUndoNewCompletion() async throws {
        let firstTemplate = TaskTemplate(title: "First")
        let secondTemplate = TaskTemplate(title: "Second")
        let firstTask = DailyTask(
            templateID: firstTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: firstTemplate.title
        )
        let secondTask = DailyTask(
            templateID: secondTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: secondTemplate.title
        )
        let fixture = makeFixture(
            templates: [firstTemplate, secondTemplate],
            tasks: [firstTask, secondTask]
        )
        try fixture.model.reload()

        let staleToken = await fixture.model.toggle(firstTask)
        let currentToken = await fixture.model.toggle(secondTask)
        await fixture.model.undo(staleToken!)

        XCTAssertNotNil(fixture.model.todayTasks.first { $0.id == firstTask.id }?.completedAt)
        XCTAssertNotNil(fixture.model.todayTasks.first { $0.id == secondTask.id }?.completedAt)
        XCTAssertEqual(fixture.model.lastCompletionUndo, currentToken)
    }

    func testCurrentUndoTokenRestoresOnlyItsTask() async throws {
        let firstTemplate = TaskTemplate(title: "First")
        let secondTemplate = TaskTemplate(title: "Second")
        let firstTask = DailyTask(
            templateID: firstTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: firstTemplate.title
        )
        let secondTask = DailyTask(
            templateID: secondTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: secondTemplate.title
        )
        let fixture = makeFixture(
            templates: [firstTemplate, secondTemplate],
            tasks: [firstTask, secondTask]
        )
        try fixture.model.reload()

        _ = await fixture.model.toggle(firstTask)
        let currentToken = await fixture.model.toggle(secondTask)
        await fixture.model.undo(currentToken!)

        XCTAssertNotNil(fixture.model.todayTasks.first { $0.id == firstTask.id }?.completedAt)
        XCTAssertNil(fixture.model.todayTasks.first { $0.id == secondTask.id }?.completedAt)
        XCTAssertNil(fixture.model.lastCompletionUndo)
    }

    func testRapidCompleteThenUncompleteRunsCompletionCommandsFIFO() async throws {
        let template = TaskTemplate(title: "Walk")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title,
            reminderMode: .once,
            reminderHour: 9,
            reminderMinute: 0
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()
        fixture.notifications.blockNextCancel()

        let complete = fixture.model.enqueueCompletion(task, completed: true)
        await fixture.notifications.waitUntilCancelIsBlocked()
        let uncomplete = fixture.model.enqueueCompletion(task, completed: false)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(fixture.notifications.maximumConcurrentCompletionSyncCount, 1)
        XCTAssertTrue(fixture.notifications.syncedTaskIDs.isEmpty)

        fixture.notifications.resumeBlockedCancel()
        _ = await complete.value
        let finalToken = await uncomplete.value

        XCTAssertEqual(fixture.notifications.maximumConcurrentCompletionSyncCount, 1)
        XCTAssertEqual(fixture.notifications.syncedTaskIDs, [task.id])
        XCTAssertNil(fixture.model.todayTasks.first?.completedAt)
        XCTAssertEqual(fixture.model.lastCompletionUndo, finalToken)
    }

    func testDifferentTaskCompletionSubmissionOrderDeterminesCurrentUndoToken() async throws {
        let firstTemplate = TaskTemplate(title: "First")
        let secondTemplate = TaskTemplate(title: "Second")
        let firstTask = DailyTask(
            templateID: firstTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: firstTemplate.title
        )
        let secondTask = DailyTask(
            templateID: secondTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: secondTemplate.title
        )
        let fixture = makeFixture(
            templates: [firstTemplate, secondTemplate],
            tasks: [firstTask, secondTask]
        )
        try fixture.model.reload()
        fixture.notifications.blockNextCancel()

        let first = fixture.model.enqueueCompletion(firstTask, completed: true)
        await fixture.notifications.waitUntilCancelIsBlocked()
        let second = fixture.model.enqueueCompletion(secondTask, completed: true)
        fixture.notifications.resumeBlockedCancel()
        _ = await first.value
        let secondToken = await second.value

        XCTAssertEqual(fixture.notifications.cancelledTaskIDs, [firstTask.id, secondTask.id])
        XCTAssertEqual(fixture.model.lastCompletionUndo, secondToken)
    }

    func testABACompletionOnlyFinalCommandClearsPendingAndPublishesUndo() async throws {
        let template = TaskTemplate(title: "Walk")
        let task = DailyTask(
            templateID: template.id,
            dayKey: day.rawValue,
            titleSnapshot: template.title,
            reminderMode: .once,
            reminderHour: 9,
            reminderMinute: 0
        )
        let fixture = makeFixture(templates: [template], tasks: [task])
        try fixture.model.reload()
        fixture.notifications.blockNextCancel()
        var presentation = CompletionPresentationState()

        let first = fixture.model.enqueueCompletion(task, completed: true)
        presentation.submit(first)
        await fixture.notifications.waitUntilCancelIsBlocked()
        let second = fixture.model.enqueueCompletion(task, completed: false)
        presentation.submit(second)
        let third = fixture.model.enqueueCompletion(task, completed: true)
        presentation.submit(third)

        fixture.notifications.resumeBlockedCancel()
        let firstToken = await first.value
        XCTAssertFalse(presentation.complete(first, token: firstToken))
        XCTAssertEqual(presentation.pending(taskID: task.id)?.commandID, third.id)
        XCTAssertNil(presentation.undoToken)

        let secondToken = await second.value
        XCTAssertFalse(presentation.complete(second, token: secondToken))
        XCTAssertEqual(presentation.pending(taskID: task.id)?.commandID, third.id)
        XCTAssertNil(presentation.undoToken)

        let thirdToken = await third.value
        XCTAssertTrue(presentation.complete(third, token: thirdToken))
        XCTAssertNil(presentation.pending(taskID: task.id))
        XCTAssertEqual(presentation.undoToken?.sourceCommandID, third.id)

        await fixture.model.undo(presentation.undoToken!)

        XCTAssertNil(fixture.model.todayTasks.first?.completedAt)
        XCTAssertNil(fixture.model.lastCompletionUndo)
    }

    func testSameTargetCommandsForDifferentTasksHaveDistinctCommandIDs() async throws {
        let firstTemplate = TaskTemplate(title: "First")
        let secondTemplate = TaskTemplate(title: "Second")
        let firstTask = DailyTask(
            templateID: firstTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: firstTemplate.title
        )
        let secondTask = DailyTask(
            templateID: secondTemplate.id,
            dayKey: day.rawValue,
            titleSnapshot: secondTemplate.title
        )
        let fixture = makeFixture(
            templates: [firstTemplate, secondTemplate],
            tasks: [firstTask, secondTask]
        )
        try fixture.model.reload()

        let first = fixture.model.enqueueCompletion(firstTask, completed: true)
        let second = fixture.model.enqueueCompletion(secondTask, completed: true)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.taskID, firstTask.id)
        XCTAssertEqual(second.taskID, secondTask.id)
        let firstToken = await first.value
        let secondToken = await second.value
        XCTAssertEqual(firstToken?.sourceCommandID, first.id)
        XCTAssertEqual(secondToken?.sourceCommandID, second.id)
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

        let result = await fixture.model.add(TaskDraft(title: "   "))

        XCTAssertEqual(result, .failure)
        XCTAssertFalse(result.shouldDismissEditor)
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
        lastProcessedDay: String? = "2026-08-12",
        settings: AppSettings? = nil,
        authorizationClient: AppModelNotificationCenterClient? = nil
    ) -> AppModelFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let provider = AppModelFixedDayProvider(now: now, calendar: calendar)
        let repository = AppModelTestRepository(
            templates: templates,
            tasks: tasks,
            settings: settings ?? AppSettings(lastProcessedDayKey: lastProcessedDay)
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
        let client = authorizationClient ?? AppModelNotificationCenterClient()
        let notificationService = NotificationService(center: client)
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
            authorizationClient: client,
            lifecycle: lifecycle
        )
    }

    private func recurringTemplate(
        title: String,
        sortIndex: Int
    ) -> TaskTemplate {
        TaskTemplate(
            title: title,
            kind: .recurring,
            recurrence: RecurrenceRule(
                frequency: .daily,
                weekdays: [],
                startDay: day
            ),
            sortIndex: sortIndex
        )
    }
}

@MainActor
private struct AppModelFixture {
    let model: AppModel
    let repository: AppModelTestRepository
    let notifications: AppModelNotificationScheduler
    let authorizationClient: AppModelNotificationCenterClient
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
    var shouldFailSettings = false
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
    func remove(_ template: TaskTemplate) {
        storedTemplates.removeAll { $0.id == template.id }
    }
    func remove(_ task: DailyTask) { storedTasks.removeAll { $0.id == task.id } }
    func settings() throws -> AppSettings {
        if shouldFailSettings { throw Failure.read }
        return storedSettings
    }
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
    private(set) var cancelledTaskIDs: [UUID] = []
    private(set) var syncedTaskIDs: [UUID] = []
    private(set) var maximumConcurrentCompletionSyncCount = 0
    private var activeCompletionSyncCount = 0
    private var shouldBlockNextCancel = false
    private var blockedCancelContinuation: CheckedContinuation<Void, Never>?
    private var blockedCancelStartWaiter: CheckedContinuation<Void, Never>?
    private var hasBlockedCancel = false
    private(set) var rebuildCallCount = 0
    private(set) var dailyReminderSyncCallCount = 0
    private(set) var maximumConcurrentRebuildCount = 0
    private var activeRebuildCount = 0
    private var shouldBlockNextRebuild = false
    private var blockedRebuildContinuation: CheckedContinuation<Void, Never>?
    private var blockedStartWaiter: CheckedContinuation<Void, Never>?
    private var hasBlockedRebuild = false

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {
        activeCompletionSyncCount += 1
        maximumConcurrentCompletionSyncCount = max(
            maximumConcurrentCompletionSyncCount,
            activeCompletionSyncCount
        )
        defer { activeCompletionSyncCount -= 1 }
        syncedTaskIDs.append(task.id)
        if shouldFailSync { throw Failure.sync }
    }

    func cancel(taskID: UUID) async {
        activeCompletionSyncCount += 1
        maximumConcurrentCompletionSyncCount = max(
            maximumConcurrentCompletionSyncCount,
            activeCompletionSyncCount
        )
        defer { activeCompletionSyncCount -= 1 }
        cancelledTaskIDs.append(taskID)
        if shouldBlockNextCancel {
            shouldBlockNextCancel = false
            hasBlockedCancel = true
            blockedCancelStartWaiter?.resume()
            blockedCancelStartWaiter = nil
            await withCheckedContinuation { continuation in
                blockedCancelContinuation = continuation
            }
        }
    }

    func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        dailyReminderSyncCallCount += 1
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

    func blockNextCancel() {
        shouldBlockNextCancel = true
    }

    func waitUntilCancelIsBlocked() async {
        if hasBlockedCancel { return }
        await withCheckedContinuation { continuation in
            blockedCancelStartWaiter = continuation
        }
    }

    func resumeBlockedCancel() {
        blockedCancelContinuation?.resume()
        blockedCancelContinuation = nil
    }
}

@MainActor
private final class AppModelNotificationCenterClient: NotificationCenterClient {
    private(set) var status: UNAuthorizationStatus
    private let grantsAuthorization: Bool
    private(set) var requestCallCount = 0

    init(
        status: UNAuthorizationStatus = .notDetermined,
        grantsAuthorization: Bool = true
    ) {
        self.status = status
        self.grantsAuthorization = grantsAuthorization
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        requestCallCount += 1
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }
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
