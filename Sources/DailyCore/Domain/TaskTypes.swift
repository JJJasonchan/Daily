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
    case monthly
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
    public var dayOfMonth: Int?
    public var startDay: LocalDay

    public init(
        frequency: RecurrenceFrequency,
        weekdays: Set<Int>,
        dayOfMonth: Int? = nil,
        startDay: LocalDay
    ) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
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
        case .monthly:
            let dom = calendar.component(.day, from: day.date(in: calendar))
            let target = dayOfMonth ?? 1
            guard let range = calendar.range(of: .day, in: .month, for: day.date(in: calendar)) else {
                return dom == target
            }
            let effective = min(target, range.last ?? 31)
            return dom == effective
        }
    }
}

public struct TaskDraft: Sendable {
    public var title: String
    public var kind: TaskKind
    public var recurrence: RecurrenceRule?
    public var scheduledDay: LocalDay?
    public var reminderMode: ReminderMode
    public var reminderHour: Int?
    public var reminderMinute: Int?

    public init(
        title: String,
        kind: TaskKind = .once,
        recurrence: RecurrenceRule? = nil,
        scheduledDay: LocalDay? = nil,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.title = title
        self.kind = kind
        self.recurrence = recurrence
        self.scheduledDay = scheduledDay
        self.reminderMode = reminderMode
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

public struct InstanceDraft: Sendable {
    public var title: String
    public var scheduledDay: LocalDay?
    public var reminderMode: ReminderMode
    public var reminderHour: Int?
    public var reminderMinute: Int?

    public init(
        title: String,
        scheduledDay: LocalDay? = nil,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.title = title
        self.scheduledDay = scheduledDay
        self.reminderMode = reminderMode
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

public enum ColorSchemeMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}
