import Foundation

@MainActor
public protocol TaskRepository: AnyObject {
    func templates(enabledOnly: Bool) throws -> [TaskTemplate]
    func template(id: UUID) throws -> TaskTemplate?
    func dailyTasks(on day: LocalDay) throws -> [DailyTask]
    func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask]
    func dailyTask(id: UUID) throws -> DailyTask?
    func insert(_ template: TaskTemplate)
    func insert(_ task: DailyTask)
    func remove(_ task: DailyTask)
    func settings() throws -> AppSettings
    func save() throws
}
