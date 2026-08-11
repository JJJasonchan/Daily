import SwiftData
import XCTest
@testable import DailyCore

@MainActor
final class SwiftDataTaskRepositoryTests: XCTestCase {
    func testSettingsCreatesAndReturnsOneSingleton() throws {
        let container = try makeContainer()
        let repository = SwiftDataTaskRepository(context: container.mainContext)

        let first = try repository.settings()
        let second = try repository.settings()
        let storedSettings = try container.mainContext.fetch(FetchDescriptor<AppSettings>())

        XCTAssertEqual(first.id, AppSettings.singletonID)
        XCTAssertEqual(second.id, AppSettings.singletonID)
        XCTAssertEqual(storedSettings.map(\.id), [AppSettings.singletonID])
    }

    func testDailyTasksOnDayFiltersByDayKeyAndSortsBySortIndex() throws {
        let container = try makeContainer()
        let repository = SwiftDataTaskRepository(context: container.mainContext)
        let templateID = UUID()
        let requestedDay = LocalDay(rawValue: "2026-08-12")
        let later = DailyTask(templateID: templateID, dayKey: requestedDay.rawValue, titleSnapshot: "Later", sortIndex: 2)
        let earlier = DailyTask(templateID: templateID, dayKey: requestedDay.rawValue, titleSnapshot: "Earlier", sortIndex: 1)
        let anotherDay = DailyTask(templateID: templateID, dayKey: "2026-08-13", titleSnapshot: "Another day", sortIndex: 0)

        repository.insert(later)
        repository.insert(earlier)
        repository.insert(anotherDay)
        try repository.save()

        let tasks = try repository.dailyTasks(on: requestedDay)

        XCTAssertEqual(tasks.map(\.id), [earlier.id, later.id])
    }

    func testEnabledTemplatesOmitsDisabledTemplates() throws {
        let container = try makeContainer()
        let repository = SwiftDataTaskRepository(context: container.mainContext)
        let enabled = TaskTemplate(title: "Enabled", sortIndex: 1, isEnabled: true)
        let disabled = TaskTemplate(title: "Disabled", sortIndex: 0, isEnabled: false)

        repository.insert(enabled)
        repository.insert(disabled)
        try repository.save()

        let templates = try repository.templates(enabledOnly: true)

        XCTAssertEqual(templates.map(\.id), [enabled.id])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TaskTemplate.self, DailyTask.self, AppSettings.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
