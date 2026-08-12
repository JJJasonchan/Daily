import Foundation
import UserNotifications
import XCTest
@testable import DailyApp
@testable import DailyCore

@MainActor
final class MenuBarStateTests: XCTestCase {
    func testWindowAndMenuBarSurfacesMutateOneSharedAppModel() async throws {
        let fixture = makeFixture()
        let task = await fixture.model.add(TaskDraft(title: "共享任务"))
        XCTAssertEqual(task, .success)
        let sceneState = AppSceneState(model: fixture.model)
        let taskID = try XCTUnwrap(sceneState.windowModel.todayTasks.first?.id)

        _ = await sceneState.menuBarModel.toggle(
            try XCTUnwrap(sceneState.menuBarModel.todayTasks.first)
        )

        XCTAssertTrue(sceneState.windowModel === sceneState.menuBarModel)
        XCTAssertEqual(sceneState.windowModel.completedCount, 1)
        XCTAssertEqual(sceneState.menuBarModel.todayTasks.first?.id, taskID)
    }

    func testQuickAddCommandReturnsToTodayAndPublishesEveryFocusRequest() {
        let fixture = makeFixture()
        let router = AppCommandRouter(model: fixture.model)
        fixture.model.destination = .history

        router.focusQuickAdd()
        let firstRequest = fixture.model.quickAddFocusRequestID
        router.focusQuickAdd()

        XCTAssertEqual(fixture.model.destination, .today)
        XCTAssertNotNil(firstRequest)
        XCTAssertNotEqual(fixture.model.quickAddFocusRequestID, firstRequest)
    }

    func testDestinationCommandsSelectAllFourSidebarDestinations() {
        let fixture = makeFixture()
        let router = AppCommandRouter(model: fixture.model)

        for destination in [
            AppModel.Destination.today,
            .rules,
            .history,
            .settings
        ] {
            router.navigate(to: destination)
            XCTAssertEqual(fixture.model.destination, destination)
        }
    }

    func testMenuBarQuickAddTrimsTitleAndMutatesSharedList() async {
        let fixture = makeFixture()
        let sceneState = AppSceneState(model: fixture.model)
        let actions = MenuBarActions(model: sceneState.menuBarModel)

        let result = await actions.quickAdd(title: "  菜单任务  ")

        XCTAssertEqual(result, .success)
        XCTAssertEqual(sceneState.windowModel.todayTasks.map(\.titleSnapshot), ["菜单任务"])
    }

    func testRepeatedSurfaceActivationKeepsOneObserverAndRefreshesCurrentState() async {
        let fixture = makeFixture()
        let sceneState = AppSceneState(model: fixture.model)

        await sceneState.activate()
        await sceneState.activate()

        XCTAssertEqual(fixture.lifecycle.startCallCount, 1)
        XCTAssertEqual(fixture.notifications.rebuildCallCount, 2)
    }

    private func makeFixture() -> MenuBarFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_786_521_600)
        let provider = MenuBarDayProvider(now: now, calendar: calendar)
        let repository = MenuBarRepository(
            settings: AppSettings(lastProcessedDayKey: "2026-08-12")
        )
        let notifications = MenuBarNotificationScheduler()
        let taskService = TaskService(repository: repository, notifications: notifications)
        let rolloverService = DayRolloverService(
            repository: repository,
            notifications: notifications,
            dayProvider: provider
        )
        let reminderSettingsService = ReminderSettingsService(
            repository: repository,
            notifications: notifications
        )
        let notificationService = NotificationService(center: MenuBarNotificationCenter())
        let lifecycle = MenuBarLifecycleObserver()
        let model = AppModel(
            taskService: taskService,
            rolloverService: rolloverService,
            reminderSettingsService: reminderSettingsService,
            repository: repository,
            dayProvider: provider,
            notificationService: notificationService,
            lifecycleObserver: lifecycle
        )
        return MenuBarFixture(
            model: model,
            notifications: notifications,
            lifecycle: lifecycle
        )
    }
}

@MainActor
private struct MenuBarFixture {
    let model: AppModel
    let notifications: MenuBarNotificationScheduler
    let lifecycle: MenuBarLifecycleObserver
}

private struct MenuBarDayProvider: DayProviding {
    let now: Date
    let calendar: Calendar
}

@MainActor
private final class MenuBarRepository: TaskRepository {
    private var templates: [TaskTemplate] = []
    private var tasks: [DailyTask] = []
    private let storedSettings: AppSettings

    init(settings: AppSettings) {
        storedSettings = settings
    }

    func templates(enabledOnly: Bool) -> [TaskTemplate] {
        templates.filter { !enabledOnly || $0.isEnabled }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func template(id: UUID) -> TaskTemplate? {
        templates.first { $0.id == id }
    }

    func dailyTasks(on day: LocalDay) -> [DailyTask] {
        tasks.filter { $0.dayKey == day.rawValue }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func dailyTasks(from start: LocalDay, through end: LocalDay) -> [DailyTask] {
        tasks.filter { start.rawValue <= $0.dayKey && $0.dayKey <= end.rawValue }
    }

    func dailyTask(id: UUID) -> DailyTask? {
        tasks.first { $0.id == id }
    }

    func insert(_ template: TaskTemplate) { templates.append(template) }
    func insert(_ task: DailyTask) { tasks.append(task) }
    func remove(_ template: TaskTemplate) { templates.removeAll { $0.id == template.id } }
    func remove(_ task: DailyTask) { tasks.removeAll { $0.id == task.id } }
    func settings() -> AppSettings { storedSettings }
    func save() {}
}

@MainActor
private final class MenuBarNotificationScheduler: NotificationScheduling {
    private(set) var rebuildCallCount = 0

    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws {}
    func cancel(taskID: UUID) async {}
    func syncDailyReminder(settings: AppSettings, now: Date) async throws {}
    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws {
        rebuildCallCount += 1
    }
}

@MainActor
private final class MenuBarNotificationCenter: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePending(ids: [String]) {}
    func pendingRequests() async -> [UNNotificationRequest] { [] }
}

@MainActor
private final class MenuBarLifecycleObserver: AppLifecycleObserving {
    private(set) var startCallCount = 0

    func start(
        handler: @escaping @MainActor @Sendable () -> Task<Void, Never>?
    ) {
        startCallCount += 1
    }

    func stop() {}
}
