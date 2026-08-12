import Foundation

public enum ReminderSettingsError: Error, Equatable {
    case invalidTime
    case invalidInterval
    case notificationSyncFailed
}

@MainActor
public final class ReminderSettingsService {
    private static let supportedIntervals: Set<Int> = [5, 10, 15, 30, 60]

    private let repository: any TaskRepository
    private let notifications: any NotificationScheduling

    public init(repository: any TaskRepository, notifications: any NotificationScheduling) {
        self.repository = repository
        self.notifications = notifications
    }

    public func settings() throws -> AppSettings {
        try repository.settings()
    }

    public func updateDailyReminder(enabled: Bool, hour: Int?, minute: Int?, now: Date) async throws {
        if enabled {
            guard
                let hour,
                let minute,
                (0...23).contains(hour),
                (0...59).contains(minute)
            else {
                throw ReminderSettingsError.invalidTime
            }
        }

        let settings = try repository.settings()
        settings.dailyReminderEnabled = enabled
        settings.dailyReminderHour = hour
        settings.dailyReminderMinute = minute
        try repository.save()

        do {
            try await notifications.syncDailyReminder(settings: settings, now: now)
        } catch {
            throw ReminderSettingsError.notificationSyncFailed
        }
    }

    public func updatePersistentInterval(minutes: Int) throws {
        guard Self.supportedIntervals.contains(minutes) else {
            throw ReminderSettingsError.invalidInterval
        }

        let settings = try repository.settings()
        settings.persistentIntervalMinutes = minutes
        try repository.save()
    }

    public func saveColorSchemeMode(_ mode: ColorSchemeMode) throws {
        let settings = try repository.settings()
        settings.colorSchemeMode = mode
        try repository.save()
    }
}
