import AppKit
import DailyCore
import Foundation
import Observation

@MainActor
protocol AppLifecycleObserving: AnyObject {
    func start(
        handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?
    )
    func stop()
}

@MainActor
final class SystemAppLifecycleObserver: AppLifecycleObserving {
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var registrations: [NotificationRegistration] = []

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func start(
        handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?
    ) {
        guard registrations.isEmpty else { return }

        let defaultCenterNames: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            NSApplication.didBecomeActiveNotification
        ]
        registrations = defaultCenterNames.map { name in
            observe(center: notificationCenter, name: name, handler: handler)
        }
        registrations.append(
            observe(
                center: workspaceNotificationCenter,
                name: NSWorkspace.didWakeNotification,
                handler: handler
            )
        )
    }

    func stop() {
        registrations.removeAll()
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?
    ) -> NotificationRegistration {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                _ = handler()
            }
        }
        return NotificationRegistration(center: center, token: token)
    }
}

private final class NotificationRegistration {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
}

@MainActor
@Observable
final class AppModel {
    enum Destination: Hashable {
        case today
        case rules
        case history
        case settings
    }

    private(set) var todayTasks: [DailyTask] = []
    private(set) var templates: [TaskTemplate] = []
    private(set) var selectedHistoryDay: LocalDay
    private(set) var errorMessage: String?
    private(set) var lastCompletionUndo: (taskID: UUID, wasCompleted: Bool)?
    var destination: Destination = .today
    var editorTaskID: UUID?
    var isPresentingNewTask = false

    private let taskService: TaskService
    private let rolloverService: DayRolloverService
    private let reminderSettingsService: ReminderSettingsService
    private let repository: any TaskRepository
    private let dayProvider: any DayProviding
    private let notificationService: NotificationService
    private let lifecycleObserver: any AppLifecycleObserving
    private let lifetimeAnchor: AnyObject?
    private var isObservingLifecycle = false
    private var lifecycleGeneration: UInt = 0
    private var refreshSequence: UInt = 0
    private var pendingRefresh: RefreshRequest?
    private var lifecycleRefreshTask: Task<Void, Never>?

    init(
        taskService: TaskService,
        rolloverService: DayRolloverService,
        reminderSettingsService: ReminderSettingsService,
        repository: any TaskRepository,
        dayProvider: any DayProviding,
        notificationService: NotificationService,
        lifecycleObserver: any AppLifecycleObserving = SystemAppLifecycleObserver(),
        lifetimeAnchor: AnyObject? = nil
    ) {
        self.taskService = taskService
        self.rolloverService = rolloverService
        self.reminderSettingsService = reminderSettingsService
        self.repository = repository
        self.dayProvider = dayProvider
        self.notificationService = notificationService
        self.lifecycleObserver = lifecycleObserver
        self.lifetimeAnchor = lifetimeAnchor
        selectedHistoryDay = LocalDay(date: dayProvider.now, calendar: dayProvider.calendar)
    }

    var completedCount: Int {
        todayTasks.lazy.filter { $0.completedAt != nil }.count
    }

    var completionFraction: Double {
        todayTasks.isEmpty ? 0 : Double(completedCount) / Double(todayTasks.count)
    }

    func start() async {
        startObservingLifecycleIfNeeded()
        let task = requestLifecycleRefresh(expectedGeneration: lifecycleGeneration)
        await task?.value
    }

    func reload() throws {
        let day = LocalDay(date: dayProvider.now, calendar: dayProvider.calendar)
        let loadedTasks = try taskService.today(on: day)
        let loadedTemplates = try taskService.recurringTemplates()
        todayTasks = loadedTasks
        templates = loadedTemplates
        errorMessage = nil
    }

    func add(_ draft: TaskDraft) async {
        do {
            _ = try await taskService.create(draft, on: today, now: dayProvider.now)
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                reloadAfterSavedMutation(
                    successMessage: "任务已保存，但提醒失败。请重试。"
                )
                return
            }
            errorMessage = addErrorMessage(for: error)
            return
        }
        reloadAfterSavedMutation()
    }

    func update(_ task: DailyTask, with draft: TaskDraft) async {
        do {
            try await taskService.update(
                templateID: task.templateID,
                draft: draft,
                on: today,
                now: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                reloadAfterSavedMutation(
                    successMessage: "任务已更新，但提醒失败。请重试。"
                )
                return
            }
            errorMessage = addErrorMessage(for: error)
            return
        }
        reloadAfterSavedMutation()
    }

    func toggle(_ task: DailyTask) async {
        let wasCompleted = task.completedAt != nil
        do {
            try await taskService.setCompleted(
                id: task.id,
                completed: !wasCompleted,
                at: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                lastCompletionUndo = (task.id, wasCompleted)
                reloadAfterSavedMutation(
                    successMessage: "任务状态已更新，但提醒失败。请重试。"
                )
                return
            }
            errorMessage = commandErrorMessage(
                for: error,
                notificationMessage: "任务状态已更新，但提醒失败。请重试。",
                fallback: "更新任务状态失败。请重试。"
            )
            return
        }
        lastCompletionUndo = (task.id, wasCompleted)
        reloadAfterSavedMutation()
    }

    func undoLastCompletion() async {
        guard let undo = lastCompletionUndo else { return }
        do {
            try await taskService.setCompleted(
                id: undo.taskID,
                completed: undo.wasCompleted,
                at: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                lastCompletionUndo = nil
                reloadAfterSavedMutation(
                    successMessage: "任务状态已恢复，但提醒失败。请重试。"
                )
                return
            }
            errorMessage = commandErrorMessage(
                for: error,
                notificationMessage: "任务状态已恢复，但提醒失败。请重试。",
                fallback: "撤销失败。请重试。"
            )
            return
        }
        lastCompletionUndo = nil
        reloadAfterSavedMutation()
    }

    func delete(_ task: DailyTask, scope: DeleteScope) async {
        do {
            try await taskService.delete(id: task.id, scope: scope)
            if lastCompletionUndo?.taskID == task.id {
                lastCompletionUndo = nil
            }
        } catch {
            errorMessage = "删除任务失败。请重试。"
            return
        }
        reloadAfterSavedMutation()
    }

    func reorder(ids: [UUID]) {
        do {
            try taskService.reorder(ids: ids)
        } catch {
            errorMessage = "调整任务顺序失败。请重试。"
            return
        }
        reloadAfterSavedMutation()
    }

    func clearError() {
        errorMessage = nil
    }

    func stopObservingLifecycle() {
        guard isObservingLifecycle else { return }
        isObservingLifecycle = false
        lifecycleGeneration &+= 1
        pendingRefresh = nil
        lifecycleObserver.stop()
    }

    private var today: LocalDay {
        LocalDay(date: dayProvider.now, calendar: dayProvider.calendar)
    }

    private func startObservingLifecycleIfNeeded() {
        guard !isObservingLifecycle else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        isObservingLifecycle = true
        lifecycleObserver.start { [weak self] in
            self?.requestLifecycleRefresh(expectedGeneration: generation)
        }
    }

    @discardableResult
    private func requestLifecycleRefresh(
        expectedGeneration: UInt
    ) -> Task<Void, Never>? {
        guard isObservingLifecycle, expectedGeneration == lifecycleGeneration else {
            return nil
        }

        refreshSequence &+= 1
        pendingRefresh = RefreshRequest(
            generation: expectedGeneration,
            sequence: refreshSequence
        )
        if lifecycleRefreshTask == nil {
            lifecycleRefreshTask = Task { @MainActor [weak self] in
                await self?.drainLifecycleRefreshes()
            }
        }
        return lifecycleRefreshTask
    }

    private func drainLifecycleRefreshes() async {
        while let request = pendingRefresh {
            pendingRefresh = nil
            guard isCurrent(request) else { continue }
            await performLifecycleRefresh(request)
        }
        lifecycleRefreshTask = nil
    }

    private func performLifecycleRefresh(_ request: RefreshRequest) async {
        do {
            try await rolloverService.processThroughToday()
            guard isCurrent(request) else { return }
            try reload()
        } catch {
            guard isCurrent(request) else { return }
            errorMessage = "更新今日任务失败。请重试。"
        }
    }

    private func isCurrent(_ request: RefreshRequest) -> Bool {
        isObservingLifecycle
            && request.generation == lifecycleGeneration
            && request.sequence == refreshSequence
    }

    private func addErrorMessage(for error: Error) -> String {
        guard let serviceError = error as? TaskServiceError else {
            return "添加任务失败。请重试。"
        }
        switch serviceError {
        case .emptyTitle:
            return "任务标题不能为空。"
        case .recurrenceRequired:
            return "重复任务需要选择重复规则。"
        case .notificationSyncFailed:
            return "任务已保存，但提醒失败。请重试。"
        case .taskNotFound, .templateNotFound:
            return "添加任务失败。请重试。"
        }
    }

    private func commandErrorMessage(
        for error: Error,
        notificationMessage: String,
        fallback: String
    ) -> String {
        if (error as? TaskServiceError) == .notificationSyncFailed {
            return notificationMessage
        }
        return fallback
    }

    private func reloadAfterSavedMutation(successMessage: String? = nil) {
        do {
            try reload()
            errorMessage = successMessage
        } catch {
            errorMessage = "任务已保存，但列表刷新失败。请重试。"
        }
    }

    private struct RefreshRequest {
        let generation: UInt
        let sequence: UInt
    }
}
