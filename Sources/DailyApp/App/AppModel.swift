import AppKit
import DailyCore
import Foundation
import Observation
import UserNotifications

enum MutationResult: Equatable, Sendable {
    case success
    case partialSuccess
    case failure

    var shouldDismissEditor: Bool {
        self != .failure
    }
}

struct CompletionUndoToken: Equatable, Sendable {
    let id: UUID
    let sourceCommandID: UUID
    let taskID: UUID
    let wasCompleted: Bool
}

struct CompletionCommand: Sendable {
    let id: UUID
    let taskID: UUID
    let targetCompletion: Bool
    private let result: Task<CompletionUndoToken?, Never>

    init(
        id: UUID,
        taskID: UUID,
        targetCompletion: Bool,
        result: Task<CompletionUndoToken?, Never>
    ) {
        self.id = id
        self.taskID = taskID
        self.targetCompletion = targetCompletion
        self.result = result
    }

    var value: CompletionUndoToken? {
        get async { await result.value }
    }
}

private struct QueuedCompletionCommand {
    let id: UUID
    let targetCompletion: Bool
}

struct HistoryDaySummary: Identifiable {
    let day: LocalDay
    let tasks: [(DailyTask, HistoryStatus)]

    var id: String { day.rawValue }
    var totalCount: Int { tasks.count }
    var completedCount: Int { tasks.lazy.filter { $0.1 == .completed }.count }
    var completionFraction: Double? {
        tasks.isEmpty ? nil : Double(completedCount) / Double(tasks.count)
    }
}

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
    private(set) var lastCompletionUndo: CompletionUndoToken?
    private(set) var dailyReminderEnabled = false
    private(set) var dailyReminderHour = 9
    private(set) var dailyReminderMinute = 0
    private(set) var persistentIntervalMinutes = 15
    private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    var destination: Destination = .today
    var editorTaskID: UUID?
    var editorTemplateID: UUID?
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
    private var completionCommandTail: Task<Void, Never>?
    private var queuedCompletionCommands: [UUID: QueuedCompletionCommand] = [:]

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

    var currentDay: LocalDay { today }

    func history(weekContaining day: LocalDay) throws -> [HistoryDaySummary] {
        let calendar = dayProvider.calendar
        let startDate = calendar.dateInterval(
            of: .weekOfYear,
            for: day.date(in: calendar)
        )?.start ?? day.date(in: calendar)
        let weekStart = LocalDay(date: startDate, calendar: calendar)
        let days = (0..<7).map { weekStart.adding(days: $0, calendar: calendar) }
        guard let weekEnd = days.last else { return [] }
        let statusLookupEnd = weekEnd.adding(days: 1, calendar: calendar)
        let allTasks = try repository.dailyTasks(
            from: weekStart,
            through: statusLookupEnd
        )

        return days.map { historyDay in
            let tasks = allTasks
                .filter { $0.dayKey == historyDay.rawValue }
                .map { task in
                    (task, rolloverService.historyStatus(for: task, allTasks: allTasks))
                }
            return HistoryDaySummary(day: historyDay, tasks: tasks)
        }
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

    func selectHistoryDay(_ day: LocalDay) {
        selectedHistoryDay = day
    }

    @discardableResult
    func add(_ draft: TaskDraft) async -> MutationResult {
        do {
            _ = try await taskService.create(draft, on: today, now: dayProvider.now)
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                reloadAfterSavedMutation(
                    successMessage: "任务已保存，但提醒失败。请重试。"
                )
                return .partialSuccess
            }
            errorMessage = addErrorMessage(for: error)
            return .failure
        }
        return reloadAfterSavedMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func update(_ task: DailyTask, with draft: TaskDraft) async -> MutationResult {
        do {
            guard try repository.template(id: task.templateID) != nil else {
                errorMessage = "重复规则已删除，只能编辑今天的任务。"
                return .failure
            }
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
                return .partialSuccess
            }
            errorMessage = addErrorMessage(for: error)
            return .failure
        }
        return reloadAfterSavedMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func updateInstance(
        _ task: DailyTask,
        with draft: InstanceDraft
    ) async -> MutationResult {
        do {
            try await taskService.updateInstance(
                id: task.id,
                draft: draft,
                now: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                reloadAfterSavedMutation(
                    successMessage: "今天的任务已更新，但提醒失败。请重试。"
                )
                return .partialSuccess
            }
            errorMessage = addErrorMessage(for: error)
            return .failure
        }
        return reloadAfterSavedMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func update(_ template: TaskTemplate, with draft: TaskDraft) async -> MutationResult {
        do {
            try await taskService.update(
                templateID: template.id,
                draft: draft,
                on: today,
                now: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                reloadAfterTemplateMutation(
                    successMessage: "重复规则已更新，但提醒失败。请重试。"
                )
                return .partialSuccess
            }
            errorMessage = templateMutationErrorMessage(
                for: error,
                fallback: "更新重复规则失败。请重试。"
            )
            return .failure
        }
        return reloadAfterTemplateMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func setTemplateEnabled(
        _ template: TaskTemplate,
        enabled: Bool
    ) -> MutationResult {
        do {
            try taskService.setTemplateEnabled(id: template.id, enabled: enabled)
        } catch {
            errorMessage = "更新重复规则状态失败。请重试。"
            return .failure
        }
        return reloadAfterTemplateMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func reorderTemplates(ids: [UUID]) -> MutationResult {
        do {
            try taskService.reorderTemplates(ids: ids)
        } catch {
            errorMessage = "调整重复规则顺序失败。请重试。"
            return .failure
        }
        return reloadAfterTemplateMutation() ? .success : .partialSuccess
    }

    @discardableResult
    func deleteTemplate(_ template: TaskTemplate) -> MutationResult {
        do {
            try taskService.deleteTemplate(id: template.id)
        } catch {
            errorMessage = "删除重复规则失败。请重试。"
            return .failure
        }
        if editorTemplateID == template.id {
            editorTemplateID = nil
        }
        return reloadAfterTemplateMutation() ? .success : .partialSuccess
    }

    func loadReminderSettings() {
        do {
            apply(try reminderSettingsService.settings())
            errorMessage = nil
        } catch {
            errorMessage = "读取提醒设置失败。请重试。"
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await notificationService.authorizationStatus()
    }

    @discardableResult
    func saveReminderSettings(
        enabled: Bool,
        hour: Int?,
        minute: Int?,
        persistentIntervalMinutes: Int
    ) async -> MutationResult {
        do {
            try reminderSettingsService.updatePersistentInterval(
                minutes: persistentIntervalMinutes
            )
        } catch {
            if (error as? ReminderSettingsError) == .invalidInterval {
                errorMessage = "持续提醒间隔仅支持 5、10、15、30 或 60 分钟。"
            } else {
                errorMessage = "保存持续提醒间隔失败。请重试。"
            }
            return .failure
        }

        do {
            try await reminderSettingsService.updateDailyReminder(
                enabled: enabled,
                hour: hour,
                minute: minute,
                now: dayProvider.now
            )
        } catch {
            if (error as? ReminderSettingsError) == .notificationSyncFailed {
                applyReminderValues(
                    enabled: enabled,
                    hour: hour,
                    minute: minute,
                    persistentIntervalMinutes: persistentIntervalMinutes
                )
                errorMessage = "设置已保存，但每日提醒安排失败。请检查通知权限后重试。"
                return .partialSuccess
            }
            if (error as? ReminderSettingsError) == .invalidTime {
                errorMessage = "持续提醒间隔已保存，但每日提醒时间无效。"
            } else {
                errorMessage = "持续提醒间隔已保存，但每日提醒设置保存失败。请重试。"
            }
            self.persistentIntervalMinutes = persistentIntervalMinutes
            return .partialSuccess
        }

        applyReminderValues(
            enabled: enabled,
            hour: hour,
            minute: minute,
            persistentIntervalMinutes: persistentIntervalMinutes
        )
        errorMessage = nil
        return .success
    }

    func requestNotificationAuthorization() async {
        do {
            _ = try await notificationService.requestAuthorization()
            notificationAuthorizationStatus = await notificationService.authorizationStatus()
            errorMessage = nil
        } catch {
            notificationAuthorizationStatus = await notificationService.authorizationStatus()
            errorMessage = "请求通知权限失败。请重试或在系统设置中调整。"
        }
    }

    @discardableResult
    func toggle(_ task: DailyTask) async -> CompletionUndoToken? {
        let currentCompletion = queuedCompletionCommands[task.id]?.targetCompletion
            ?? (task.completedAt != nil)
        return await enqueueCompletion(
            task,
            completed: !currentCompletion
        ).value
    }

    func enqueueCompletion(
        _ task: DailyTask,
        completed: Bool
    ) -> CompletionCommand {
        let predecessor = completionCommandTail
        let commandID = UUID()
        queuedCompletionCommands[task.id] = QueuedCompletionCommand(
            id: commandID,
            targetCompletion: completed
        )
        let command = Task<CompletionUndoToken?, Never> { @MainActor [weak self] in
            await predecessor?.value
            guard let self else { return nil }
            let token = await performSetCompletion(
                commandID: commandID,
                taskID: task.id,
                completed: completed,
                wasCompleted: !completed
            )
            if queuedCompletionCommands[task.id]?.id == commandID {
                queuedCompletionCommands[task.id] = nil
            }
            return token
        }
        completionCommandTail = Task { @MainActor in
            _ = await command.value
        }
        return CompletionCommand(
            id: commandID,
            taskID: task.id,
            targetCompletion: completed,
            result: command
        )
    }

    private func performSetCompletion(
        commandID: UUID,
        taskID: UUID,
        completed: Bool,
        wasCompleted: Bool
    ) async -> CompletionUndoToken? {
        let undoToken = CompletionUndoToken(
            id: UUID(),
            sourceCommandID: commandID,
            taskID: taskID,
            wasCompleted: wasCompleted
        )
        do {
            try await taskService.setCompleted(
                id: taskID,
                completed: completed,
                at: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                lastCompletionUndo = undoToken
                reloadAfterSavedMutation(
                    successMessage: "任务状态已更新，但提醒失败。请重试。"
                )
                return undoToken
            }
            errorMessage = commandErrorMessage(
                for: error,
                notificationMessage: "任务状态已更新，但提醒失败。请重试。",
                fallback: "更新任务状态失败。请重试。"
            )
            return nil
        }
        lastCompletionUndo = undoToken
        reloadAfterSavedMutation()
        return undoToken
    }

    func undo(_ token: CompletionUndoToken) async {
        await enqueueUndo(token).value
    }

    func enqueueUndo(_ token: CompletionUndoToken) -> Task<Void, Never> {
        let predecessor = completionCommandTail
        let command = Task { @MainActor [weak self] in
            await predecessor?.value
            await self?.performUndo(token)
        }
        completionCommandTail = command
        return command
    }

    private func performUndo(_ token: CompletionUndoToken) async {
        guard lastCompletionUndo == token else { return }
        do {
            try await taskService.setCompleted(
                id: token.taskID,
                completed: token.wasCompleted,
                at: dayProvider.now
            )
        } catch {
            if (error as? TaskServiceError) == .notificationSyncFailed {
                if lastCompletionUndo == token {
                    lastCompletionUndo = nil
                }
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
        if lastCompletionUndo == token {
            lastCompletionUndo = nil
        }
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

    private func templateMutationErrorMessage(
        for error: Error,
        fallback: String
    ) -> String {
        guard let serviceError = error as? TaskServiceError else { return fallback }
        switch serviceError {
        case .emptyTitle:
            return "任务标题不能为空。"
        case .recurrenceRequired:
            return "重复任务需要选择重复规则。"
        case .taskNotFound, .templateNotFound, .notificationSyncFailed:
            return fallback
        }
    }

    private func apply(_ settings: AppSettings) {
        dailyReminderEnabled = settings.dailyReminderEnabled
        dailyReminderHour = settings.dailyReminderHour ?? 9
        dailyReminderMinute = settings.dailyReminderMinute ?? 0
        persistentIntervalMinutes = settings.persistentIntervalMinutes
    }

    private func applyReminderValues(
        enabled: Bool,
        hour: Int?,
        minute: Int?,
        persistentIntervalMinutes: Int
    ) {
        dailyReminderEnabled = enabled
        dailyReminderHour = hour ?? dailyReminderHour
        dailyReminderMinute = minute ?? dailyReminderMinute
        self.persistentIntervalMinutes = persistentIntervalMinutes
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

    @discardableResult
    private func reloadAfterSavedMutation(successMessage: String? = nil) -> Bool {
        do {
            try reload()
            errorMessage = successMessage
            return true
        } catch {
            errorMessage = "任务已保存，但列表刷新失败。请重试。"
            return false
        }
    }

    @discardableResult
    private func reloadAfterTemplateMutation(successMessage: String? = nil) -> Bool {
        do {
            try reload()
            errorMessage = successMessage
            return true
        } catch {
            errorMessage = "重复规则已保存，但列表刷新失败。请重试。"
            return false
        }
    }

    private struct RefreshRequest {
        let generation: UInt
        let sequence: UInt
    }
}
