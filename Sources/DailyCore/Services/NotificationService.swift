import Foundation
import UserNotifications

@MainActor
public protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(ids: [String])
    func pendingRequests() async -> [UNNotificationRequest]
}

@MainActor
public final class UserNotificationCenterClient: NotificationCenterClient {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePending(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}

public enum NotificationID {
    public static let daily = "daily.summary"

    public static func task(_ id: UUID, sequence: Int) -> String {
        "task.\(id.uuidString).\(sequence)"
    }
}

@MainActor
public final class NotificationService: NotificationScheduling {
    private static let persistentRequestCount = 8
    private static let taskCategoryIdentifier = "TASK_REMINDER"

    private let center: any NotificationCenterClient
    private let calendar: Calendar

    public init(center: any NotificationCenterClient, calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization()
    }

    public func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {
        await cancel(taskID: task.id)
        guard task.completedAt == nil else { return }

        switch task.reminderMode {
        case .none:
            return
        case .once:
            guard let nominalDate = nominalDate(for: task), isFutureSameDay(nominalDate, relativeTo: now) else {
                return
            }
            try await addTaskRequest(
                task: task,
                sequence: 0,
                trigger: calendarTrigger(at: nominalDate)
            )
        case .persistent:
            try await schedulePersistent(task: task, intervalMinutes: persistentIntervalMinutes, now: now)
        }
    }

    public func cancel(taskID: UUID) async {
        let prefix = taskPrefix(taskID)
        let ids = await center.pendingRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePending(ids: ids)
        }
    }

    public func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        center.removePending(ids: [NotificationID.daily])
        guard
            settings.dailyReminderEnabled,
            let hour = settings.dailyReminderHour,
            let minute = settings.dailyReminderMinute,
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Daily"
        content.body = "查看今天的任务并开始行动。"
        content.sound = .default

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try await center.add(UNNotificationRequest(identifier: NotificationID.daily, content: content, trigger: trigger))
    }

    public func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        let staleIDs = await center.pendingRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("task.") }
        if !staleIDs.isEmpty {
            center.removePending(ids: staleIDs)
        }

        let todayKey = LocalDay(date: now, calendar: calendar).rawValue
        for task in tasks where task.dayKey == todayKey && task.completedAt == nil {
            try await sync(task: task, persistentIntervalMinutes: settings.persistentIntervalMinutes, now: now)
        }
        try await syncDailyReminder(settings: settings, now: now)
    }

    private func schedulePersistent(task: DailyTask, intervalMinutes: Int, now: Date) async throws {
        guard intervalMinutes > 0, let nominalDate = nominalDate(for: task) else { return }

        let interval = TimeInterval(intervalMinutes * 60)
        if isFutureSameDay(nominalDate, relativeTo: now) {
            try await addTaskRequest(task: task, sequence: 0, trigger: calendarTrigger(at: nominalDate))
            for sequence in 1..<Self.persistentRequestCount {
                let delay = nominalDate.timeIntervalSince(now) + (TimeInterval(sequence) * interval)
                try await addTaskRequest(
                    task: task,
                    sequence: sequence,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        } else {
            for sequence in 0..<Self.persistentRequestCount {
                let delay = TimeInterval(sequence + 1) * interval
                try await addTaskRequest(
                    task: task,
                    sequence: sequence,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        }
    }

    private func addTaskRequest(task: DailyTask, sequence: Int, trigger: UNNotificationTrigger) async throws {
        let content = UNMutableNotificationContent()
        content.title = task.titleSnapshot
        content.sound = .default
        content.categoryIdentifier = Self.taskCategoryIdentifier
        let request = UNNotificationRequest(
            identifier: NotificationID.task(task.id, sequence: sequence),
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    private func nominalDate(for task: DailyTask) -> Date? {
        guard
            let hour = task.reminderHour,
            let minute = task.reminderMinute,
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }

        let dayParts = task.dayKey.split(separator: "-").compactMap { Int($0) }
        guard dayParts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = dayParts[0]
        components.month = dayParts[1]
        components.day = dayParts[2]
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private func isFutureSameDay(_ date: Date, relativeTo now: Date) -> Bool {
        date > now && calendar.isDate(date, inSameDayAs: now)
    }

    private func calendarTrigger(at date: Date) -> UNCalendarNotificationTrigger {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func taskPrefix(_ id: UUID) -> String {
        "task.\(id.uuidString)."
    }
}
