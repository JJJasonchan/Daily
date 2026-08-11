import Foundation
import SwiftData

@MainActor
public final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func templates(enabledOnly: Bool) throws -> [TaskTemplate] {
        let sortBy = [SortDescriptor(\TaskTemplate.sortIndex)]

        if enabledOnly {
            let descriptor = FetchDescriptor<TaskTemplate>(
                predicate: #Predicate { $0.isEnabled },
                sortBy: sortBy
            )
            return try context.fetch(descriptor)
        }

        return try context.fetch(FetchDescriptor(sortBy: sortBy))
    }

    public func template(id: UUID) throws -> TaskTemplate? {
        let descriptor = FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func dailyTasks(on day: LocalDay) throws -> [DailyTask] {
        let dayKey = day.rawValue
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\DailyTask.sortIndex)]
        )
        return try context.fetch(descriptor)
    }

    public func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask] {
        let startDayKey = start.rawValue
        let endDayKey = end.rawValue
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { task in
                task.dayKey >= startDayKey && task.dayKey <= endDayKey
            },
            sortBy: [SortDescriptor(\DailyTask.sortIndex)]
        )
        return try context.fetch(descriptor)
    }

    public func dailyTask(id: UUID) throws -> DailyTask? {
        let descriptor = FetchDescriptor<DailyTask>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func insert(_ template: TaskTemplate) {
        context.insert(template)
    }

    public func insert(_ task: DailyTask) {
        context.insert(task)
    }

    public func remove(_ task: DailyTask) {
        context.delete(task)
    }

    public func settings() throws -> AppSettings {
        let singletonID = AppSettings.singletonID
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.id == singletonID })

        if let settings = try context.fetch(descriptor).first {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    public func save() throws {
        try context.save()
    }
}
