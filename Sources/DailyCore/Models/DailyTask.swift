import Foundation
import SwiftData

@Model
public final class DailyTask {
    @Attribute(.unique) public var id: UUID
    public var templateID: UUID
    public var dayKey: String
    public var titleSnapshot: String
    private var reminderModeRaw: String
    public var reminderHour: Int?
    public var reminderMinute: Int?
    public var sortIndex: Int
    public var completedAt: Date?
    public var rolloverOriginID: UUID?
    public var originalDayKey: String
    public var rolloverCount: Int
    public var createdAt: Date
    public var scheduledDayKey: String?

    public init(
        id: UUID = UUID(),
        templateID: UUID,
        dayKey: String,
        titleSnapshot: String,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil,
        sortIndex: Int = 0,
        completedAt: Date? = nil,
        rolloverOriginID: UUID? = nil,
        originalDayKey: String? = nil,
        rolloverCount: Int = 0,
        createdAt: Date = .now,
        scheduledDayKey: String? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.dayKey = dayKey
        self.titleSnapshot = titleSnapshot
        self.reminderModeRaw = reminderMode.rawValue
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.sortIndex = sortIndex
        self.completedAt = completedAt
        self.rolloverOriginID = rolloverOriginID
        self.originalDayKey = originalDayKey ?? dayKey
        self.rolloverCount = rolloverCount
        self.createdAt = createdAt
        self.scheduledDayKey = scheduledDayKey
    }

    public var reminderMode: ReminderMode {
        get { ReminderMode(rawValue: reminderModeRaw)! }
        set { reminderModeRaw = newValue.rawValue }
    }
}
