import XCTest
@testable import DailyCore

final class LocalDayTests: XCTestCase {
    func testRoundTripUsesCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T16:30:00Z"))

        let day = LocalDay(date: date, calendar: calendar)

        XCTAssertEqual(day.rawValue, "2026-08-13")
        XCTAssertEqual(LocalDay(date: day.date(in: calendar), calendar: calendar), day)
    }
}
