import AppKit
import DailyCore
import Foundation
import Observation

@MainActor
protocol AppLifecycleObserving: AnyObject {
    func start(handler: @escaping @MainActor @Sendable () async -> Void)
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

    func start(handler: @escaping @MainActor @Sendable () async -> Void) {
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
        handler: @escaping @MainActor @Sendable () async -> Void
    ) -> NotificationRegistration {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                await handler()
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
        do {
            try await rolloverService.processThroughToday()
            try reload()
        } catch {
            errorMessage = "更新今日任务失败。请重试。"
        }
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
            try reload()
        } catch {
            errorMessage = addErrorMessage(for: error)
        }
    }

    func toggle(_ task: DailyTask) async {
        let wasCompleted = task.completedAt != nil
        do {
            try await taskService.setCompleted(
                id: task.id,
                completed: !wasCompleted,
                at: dayProvider.now
            )
            try reload()
            lastCompletionUndo = (task.id, wasCompleted)
        } catch {
            errorMessage = commandErrorMessage(
                for: error,
                notificationMessage: "任务状态已更新，但提醒未能安排。请重试。",
                fallback: "更新任务状态失败。请重试。"
            )
        }
    }

    func undoLastCompletion() async {
        guard let undo = lastCompletionUndo else { return }
        do {
            try await taskService.setCompleted(
                id: undo.taskID,
                completed: undo.wasCompleted,
                at: dayProvider.now
            )
            try reload()
            lastCompletionUndo = nil
        } catch {
            errorMessage = commandErrorMessage(
                for: error,
                notificationMessage: "任务状态已恢复，但提醒未能安排。请重试。",
                fallback: "撤销失败。请重试。"
            )
        }
    }

    func delete(_ task: DailyTask, scope: DeleteScope) async {
        do {
            try await taskService.delete(id: task.id, scope: scope)
            try reload()
            if lastCompletionUndo?.taskID == task.id {
                lastCompletionUndo = nil
            }
        } catch {
            errorMessage = "删除任务失败。请重试。"
        }
    }

    func reorder(ids: [UUID]) {
        do {
            try taskService.reorder(ids: ids)
            try reload()
        } catch {
            errorMessage = "调整任务顺序失败。请重试。"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func stopObservingLifecycle() {
        guard isObservingLifecycle else { return }
        lifecycleObserver.stop()
        isObservingLifecycle = false
    }

    private var today: LocalDay {
        LocalDay(date: dayProvider.now, calendar: dayProvider.calendar)
    }

    private func startObservingLifecycleIfNeeded() {
        guard !isObservingLifecycle else { return }
        lifecycleObserver.start { [weak self] in
            await self?.start()
        }
        isObservingLifecycle = true
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
            return "任务已保存，但提醒未能安排。请重试。"
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
}
