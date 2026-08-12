import Foundation

public enum TaskKind: String, Codable, Sendable {
    case once
    case recurring
}

public enum ReminderMode: String, Codable, Sendable {
    case none
    case once
    case persistent
}

public enum RecurrenceFrequency: String, Codable, Sendable {
    case daily
    case weekdays
    case selectedWeekdays
}

public enum DeleteScope: Sendable {
    case todayOnly
    case allFuture
}

public enum HistoryStatus: Equatable, Sendable {
    case completed
    case incomplete
    case rolledOver
}

public struct RecurrenceRule: Codable, Equatable, Sendable {
    public var frequency: RecurrenceFrequency
    public var weekdays: Set<Int>
    public var startDay: LocalDay

    public init(
        frequency: RecurrenceFrequency,
        weekdays: Set<Int>,
        startDay: LocalDay
    ) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.startDay = startDay
    }

    public func matches(_ day: LocalDay, calendar: Calendar) -> Bool {
        guard day >= startDay else { return false }

        let weekday = calendar.component(.weekday, from: day.date(in: calendar))
        switch frequency {
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(weekday)
        case .selectedWeekdays:
            return weekdays.contains(weekday)
        }
    }
}

public struct TaskDraft: Sendable {
    public var title: String
    public var kind: TaskKind
    public var recurrence: RecurrenceRule?
    public var reminderMode: ReminderMode
    public var reminderHour: Int?
    public var reminderMinute: Int?

    public init(
        title: String,
        kind: TaskKind = .once,
        recurrence: RecurrenceRule? = nil,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.title = title
        self.kind = kind
        self.recurrence = recurrence
        self.reminderMode = reminderMode
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

public struct InstanceDraft: Sendable {
    public var title: String
    public var reminderMode: ReminderMode
    public var reminderHour: Int?
    public var reminderMinute: Int?

    public init(
        title: String,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.title = title
        self.reminderMode = reminderMode
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}
