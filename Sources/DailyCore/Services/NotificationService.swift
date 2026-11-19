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
    public nonisolated static let persistentRequestCount = 8
    private static let taskCategoryIdentifier = "TASK_REMINDER"

    private let center: any NotificationCenterClient
    private let calendar: Calendar
    private var isMutating = false
    private var waitingMutations: [CheckedContinuation<Void, Never>] = []

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
        let taskID = task.id
        let requests = taskRequests(
            for: task, intervalMinutes: persistentIntervalMinutes, now: now
        )
        await beginMutation()
        defer { endMutation() }
        await removeRequests(withPrefix: taskPrefix(taskID))
        for request in requests {
            try await center.add(request)
        }
    }

    public func cancel(taskID: UUID) async {
        await beginMutation()
        defer { endMutation() }
        await removeRequests(withPrefix: taskPrefix(taskID))
    }

    public func syncDailyReminder(settings: AppSettings, now: Date) async throws {
        let request = dailyReminderRequest(for: settings)
        await beginMutation()
        defer { endMutation() }
        try await replaceDailyReminder(with: request)
    }

    public func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        let todayKey = LocalDay(date: now, calendar: calendar).rawValue
        let requests = tasks.filter { $0.dayKey >= todayKey }.flatMap { task in
            taskRequests(for: task, intervalMinutes: settings.persistentIntervalMinutes, now: now)
        }
        let dailyRequest = dailyReminderRequest(for: settings)

        await beginMutation()
        defer { endMutation() }
        await removeRequests(withPrefix: "task.")
        for request in requests {
            try await center.add(request)
        }
        try await replaceDailyReminder(with: dailyRequest)
    }

    // Notification center calls suspend. Keep each replacement atomic with
    // respect to the other mutations submitted by the app.
    private func beginMutation() async {
        if !isMutating {
            isMutating = true
            return
        }
        await withCheckedContinuation { waitingMutations.append($0) }
    }

    private func endMutation() {
        if waitingMutations.isEmpty {
            isMutating = false
        } else {
            waitingMutations.removeFirst().resume()
        }
    }

    private func removeRequests(withPrefix prefix: String) async {
        let ids = await center.pendingRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePending(ids: ids)
        }
    }

    private func replaceDailyReminder(with request: UNNotificationRequest?) async throws {
        center.removePending(ids: [NotificationID.daily])
        if let request {
            try await center.add(request)
        }
    }

    private func dailyReminderRequest(for settings: AppSettings) -> UNNotificationRequest? {
        guard
            settings.dailyReminderEnabled,
            let hour = settings.dailyReminderHour,
            let minute = settings.dailyReminderMinute,
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
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
        return UNNotificationRequest(identifier: NotificationID.daily, content: content, trigger: trigger)
    }

    private func taskRequests(
        for task: DailyTask, intervalMinutes: Int, now: Date
    ) -> [UNNotificationRequest] {
        guard task.completedAt == nil, let nominalDate = nominalDate(for: task) else { return [] }

        switch task.reminderMode {
        case .none:
            return []
        case .once:
            guard nominalDate > now else { return [] }
            return [taskRequest(task: task, sequence: 0, trigger: calendarTrigger(at: nominalDate, using: calendar))]
        case .persistent:
            guard intervalMinutes > 0 else { return [] }
            let interval = TimeInterval(intervalMinutes) * 60
            // UTC disambiguates an absolute time when the local hour repeats.
            var triggerCalendar = Calendar(identifier: .gregorian)
            triggerCalendar.timeZone = .gmt
            return (0..<Self.persistentRequestCount).compactMap { sequence in
                let date = nominalDate.addingTimeInterval(TimeInterval(sequence) * interval)
                guard date > now, LocalDay(date: date, calendar: calendar).rawValue == task.dayKey else {
                    return nil
                }
                return taskRequest(
                    task: task, sequence: sequence, trigger: calendarTrigger(at: date, using: triggerCalendar)
                )
            }
        }
    }

    private func taskRequest(
        task: DailyTask, sequence: Int, trigger: UNNotificationTrigger
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.titleSnapshot
        content.sound = .default
        content.categoryIdentifier = Self.taskCategoryIdentifier
        return UNNotificationRequest(
            identifier: NotificationID.task(task.id, sequence: sequence),
            content: content,
            trigger: trigger
        )
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

    private func calendarTrigger(at date: Date, using calendar: Calendar) -> UNCalendarNotificationTrigger {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func taskPrefix(_ id: UUID) -> String {
        "task.\(id.uuidString)."
    }
}
