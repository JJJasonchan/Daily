import Foundation
@testable import DailyCore

@MainActor
final class TestTaskRepository: TaskRepository {
    var storedTemplates: [TaskTemplate]
    var storedTasks: [DailyTask]
    var storedSettings: AppSettings
    private(set) var saveCallCount = 0

    init(
        templates: [TaskTemplate] = [],
        tasks: [DailyTask] = [],
        settings: AppSettings = AppSettings()
    ) {
        storedTemplates = templates
        storedTasks = tasks
        storedSettings = settings
    }

    func templates(enabledOnly: Bool) throws -> [TaskTemplate] {
        storedTemplates
            .filter { !enabledOnly || $0.isEnabled }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func template(id: UUID) throws -> TaskTemplate? {
        storedTemplates.first { $0.id == id }
    }

    func dailyTasks(on day: LocalDay) throws -> [DailyTask] {
        storedTasks
            .filter { $0.dayKey == day.rawValue }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask] {
        storedTasks
            .filter { start.rawValue <= $0.dayKey && $0.dayKey <= end.rawValue }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func dailyTask(id: UUID) throws -> DailyTask? {
        storedTasks.first { $0.id == id }
    }

    func insert(_ template: TaskTemplate) {
        storedTemplates.append(template)
    }

    func insert(_ task: DailyTask) {
        storedTasks.append(task)
    }

    func remove(_ task: DailyTask) {
        storedTasks.removeAll { $0.id == task.id }
    }

    func settings() throws -> AppSettings {
        storedSettings
    }

    func save() throws {
        saveCallCount += 1
    }
}

@MainActor
final class RecordingNotificationScheduler: NotificationScheduling {
    enum Failure: Error {
        case sync
    }

    private(set) var syncedTaskIDs: [UUID] = []
    private(set) var persistentIntervals: [Int] = []
    private(set) var cancelledTaskIDs: [UUID] = []
    var shouldFailSync = false

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {
        syncedTaskIDs.append(task.id)
        persistentIntervals.append(persistentIntervalMinutes)
        if shouldFailSync {
            throw Failure.sync
        }
    }

    func cancel(taskID: UUID) async {
        cancelledTaskIDs.append(taskID)
    }

    func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        if shouldFailSync {
            throw Failure.sync
        }
    }

    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        if shouldFailSync {
            throw Failure.sync
        }
    }
}
