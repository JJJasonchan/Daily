import Foundation

public struct LocalDay: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public func date(in calendar: Calendar) -> Date {
        let values = rawValue.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))!
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        LocalDay(date: calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.rawValue < rhs.rawValue }
}
