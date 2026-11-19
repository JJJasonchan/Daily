import Foundation
import SwiftData

@Model
public final class TaskTemplate {
    @Attribute(.unique) public var id: UUID
    public var title: String
    private var kindRaw: String
    private var recurrenceData: Data?
    private var reminderModeRaw: String
    public var reminderHour: Int?
    public var reminderMinute: Int?
    public var sortIndex: Int
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date
    private var priorityRaw: String?
    public var assignee: String?

    public init(
        id: UUID = UUID(),
        title: String,
        kind: TaskKind = .once,
        recurrence: RecurrenceRule? = nil,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil,
        sortIndex: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        priority: TaskPriority? = nil,
        assignee: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.recurrenceData = try? recurrence.map { try JSONEncoder().encode($0) }
        self.reminderModeRaw = reminderMode.rawValue
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.priorityRaw = priority?.rawValue
        self.assignee = assignee
    }

    public var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw)! }
        set { kindRaw = newValue.rawValue }
    }

    public var recurrence: RecurrenceRule? {
        get { recurrenceData.flatMap { try? JSONDecoder().decode(RecurrenceRule.self, from: $0) } }
        set { recurrenceData = try? newValue.map { try JSONEncoder().encode($0) } }
    }

    public var reminderMode: ReminderMode {
        get { ReminderMode(rawValue: reminderModeRaw)! }
        set { reminderModeRaw = newValue.rawValue }
    }

    public var priority: TaskPriority? {
        get { priorityRaw.flatMap(TaskPriority.init(rawValue:)) }
        set { priorityRaw = newValue?.rawValue }
    }
}
