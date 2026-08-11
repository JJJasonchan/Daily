import Foundation

@MainActor
public protocol NotificationScheduling: AnyObject {
    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws
    func cancel(taskID: UUID) async
    func syncDailyReminder(settings: AppSettings, now: Date) async throws
    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws
}
