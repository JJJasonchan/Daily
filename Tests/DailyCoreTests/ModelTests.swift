import XCTest
import DailyCore

final class ModelTests: XCTestCase {
    func testTemplateRoundTripsTypedKindRecurrenceAndReminder() {
        let initialRule = RecurrenceRule(
            frequency: .selectedWeekdays,
            weekdays: [2, 4],
            startDay: LocalDay(rawValue: "2026-08-10")
        )
        let updatedRule = RecurrenceRule(
            frequency: .daily,
            weekdays: [],
            startDay: LocalDay(rawValue: "2026-08-12")
        )
        let template = TaskTemplate(
            title: "Review",
            kind: .recurring,
            recurrence: initialRule,
            reminderMode: .persistent
        )

        XCTAssertEqual(template.kind, .recurring)
        XCTAssertEqual(template.recurrence, initialRule)
        XCTAssertEqual(template.reminderMode, .persistent)

        template.kind = .once
        template.recurrence = updatedRule
        template.reminderMode = .once

        XCTAssertEqual(template.kind, .once)
        XCTAssertEqual(template.recurrence, updatedRule)
        XCTAssertEqual(template.reminderMode, .once)
    }

    func testDailyTaskRoundTripsTypedReminderMode() {
        let task = DailyTask(
            templateID: UUID(),
            dayKey: "2026-08-12",
            titleSnapshot: "Review",
            reminderMode: .persistent
        )

        XCTAssertEqual(task.reminderMode, .persistent)

        task.reminderMode = .once

        XCTAssertEqual(task.reminderMode, .once)
    }
}
