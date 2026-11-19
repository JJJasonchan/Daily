import Foundation

public enum HistoryAnalytics {
    /// 返回每一天的完成率（当天无任务时为 nil）。
    public static func completionFractions(
        tasks: [DailyTask],
        days: [LocalDay]
    ) -> [(LocalDay, Double?)] {
        let tasksByDay = Dictionary(grouping: tasks, by: \.dayKey)
        return days.map { day -> (LocalDay, Double?) in
            let dayTasks = tasksByDay[day.rawValue] ?? []
            guard !dayTasks.isEmpty else { return (day, nil) }
            let completed = dayTasks.lazy.filter { $0.completedAt != nil }.count
            return (day, Double(completed) / Double(dayTasks.count))
        }
    }

    /// 从 ending 向前统计“连续完全完成”的天数（每天至少 1 个任务且全部完成）。
    /// 已结束的无任务日或未全部完成日会中断。仍在进行的结束日可延后到次日判定。
    public static func currentStreak(
        tasks: [DailyTask],
        ending: LocalDay,
        calendar: Calendar,
        endingDayIsInProgress: Bool = false
    ) -> Int {
        let tasksByDay = Dictionary(grouping: tasks, by: \.dayKey)
        var streak = 0
        let endingTasks = tasksByDay[ending.rawValue] ?? []
        let endingDayComplete = !endingTasks.isEmpty && endingTasks.allSatisfy { $0.completedAt != nil }
        var day = endingDayIsInProgress && !endingDayComplete
            ? ending.adding(days: -1, calendar: calendar)
            : ending
        while let dayTasks = tasksByDay[day.rawValue], !dayTasks.isEmpty {
            guard dayTasks.allSatisfy({ $0.completedAt != nil }) else { break }
            streak += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return streak
    }

    /// 在 [ending - (days - 1), ending] 窗口内统计最长连续完全完成天数。
    public static func longestStreak(
        tasks: [DailyTask],
        ending: LocalDay,
        within days: Int,
        calendar: Calendar
    ) -> Int {
        guard days > 0 else { return 0 }
        let tasksByDay = Dictionary(grouping: tasks, by: \.dayKey)
        var longest = 0
        var current = 0
        var day = ending.adding(days: -(days - 1), calendar: calendar)
        for _ in 0..<days {
            if let dayTasks = tasksByDay[day.rawValue], !dayTasks.isEmpty,
               dayTasks.allSatisfy({ $0.completedAt != nil }) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return longest
    }
}
