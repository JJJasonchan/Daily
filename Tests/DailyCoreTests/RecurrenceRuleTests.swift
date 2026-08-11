import XCTest
@testable import DailyCore

final class RecurrenceRuleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testDailyMatchesEveryDayFromStart() {
        let rule = RecurrenceRule(frequency: .daily, weekdays: [], startDay: LocalDay(rawValue: "2026-08-12"))
        XCTAssertFalse(rule.matches(LocalDay(rawValue: "2026-08-11"), calendar: calendar))
        XCTAssertTrue(rule.matches(LocalDay(rawValue: "2026-08-12"), calendar: calendar))
        XCTAssertTrue(rule.matches(LocalDay(rawValue: "2026-08-13"), calendar: calendar))
    }

    func testWeekdaysExcludeSaturdayAndSunday() {
        let rule = RecurrenceRule(frequency: .weekdays, weekdays: [], startDay: LocalDay(rawValue: "2026-08-10"))
        XCTAssertTrue(rule.matches(LocalDay(rawValue: "2026-08-14"), calendar: calendar))
        XCTAssertFalse(rule.matches(LocalDay(rawValue: "2026-08-15"), calendar: calendar))
    }

    func testSelectedWeekdaysUseCalendarWeekdayValues() {
        let rule = RecurrenceRule(frequency: .selectedWeekdays, weekdays: [2, 4], startDay: LocalDay(rawValue: "2026-08-10"))
        XCTAssertTrue(rule.matches(LocalDay(rawValue: "2026-08-10"), calendar: calendar))
        XCTAssertFalse(rule.matches(LocalDay(rawValue: "2026-08-11"), calendar: calendar))
        XCTAssertTrue(rule.matches(LocalDay(rawValue: "2026-08-12"), calendar: calendar))
    }
}
