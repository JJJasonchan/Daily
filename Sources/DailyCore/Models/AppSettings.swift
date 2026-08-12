import Foundation
import SwiftData

@Model
public final class AppSettings {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Attribute(.unique) public var id: UUID
    public var dailyReminderEnabled: Bool
    public var dailyReminderHour: Int?
    public var dailyReminderMinute: Int?
    public var persistentIntervalMinutes: Int
    public var lastProcessedDayKey: String?
    public var colorSchemeModeRaw: String

    public var colorSchemeMode: ColorSchemeMode {
        get { ColorSchemeMode(rawValue: colorSchemeModeRaw) ?? .system }
        set { colorSchemeModeRaw = newValue.rawValue }
    }

    public init(
        id: UUID = AppSettings.singletonID,
        dailyReminderEnabled: Bool = false,
        dailyReminderHour: Int? = nil,
        dailyReminderMinute: Int? = nil,
        persistentIntervalMinutes: Int = 15,
        lastProcessedDayKey: String? = nil,
        colorSchemeMode: ColorSchemeMode = .system
    ) {
        self.id = id
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
        self.persistentIntervalMinutes = persistentIntervalMinutes
        self.lastProcessedDayKey = lastProcessedDayKey
        self.colorSchemeModeRaw = colorSchemeMode.rawValue
    }
}
