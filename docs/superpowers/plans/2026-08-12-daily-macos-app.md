# Daily macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only macOS 26 task app with a unified daily list, recurring tasks, rollover, reminders, history, menu-bar access, and a TickTick-inspired monochrome Liquid Glass interface.

**Architecture:** Use a Swift package with a reusable `DailyCore` library and a `DailyApp` executable. SwiftData models remain behind repository protocols; task, rollover, and notification behavior live in focused services; a single `AppModel` exposes state to both the main window and `MenuBarExtra`. Build an ad-hoc signed `.app` bundle with a repository script so notification behavior can be verified outside `swift run`.

**Tech Stack:** Swift 6.3, SwiftUI, Observation, SwiftData, UserNotifications, Swift Package Manager, XCTest, macOS 26 Liquid Glass APIs.

## Global Constraints

- Minimum deployment target is macOS 26.
- Runtime network access, accounts, cloud sync, analytics, and third-party dependencies are forbidden.
- Today shows one unified task list; it never groups tasks by one-time or recurring origin.
- Main window and menu-bar panel share one `AppModel` and update immediately.
- Primary colors are black, white, and neutral gray; semantic system colors are reserved for warnings and errors.
- Use native `glassEffect`, `GlassEffectContainer`, `glassEffectID`, and interactive glass; do not simulate Liquid Glass.
- Default motion uses interruptible springs; honor Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver, and keyboard navigation.
- Use test-driven development, run the focused test before and after each implementation, and commit after every task.
- Preserve the approved design in `docs/superpowers/specs/2026-08-12-daily-todo-macos-design.md`.

---

## File Map

```text
Package.swift                                  SwiftPM products, targets, macOS 26 floor
Sources/DailyCore/Domain/LocalDay.swift        Stable local date key and calendar conversion
Sources/DailyCore/Domain/TaskTypes.swift       Enums, recurrence rules, drafts, history status
Sources/DailyCore/Models/TaskTemplate.swift    SwiftData task source model
Sources/DailyCore/Models/DailyTask.swift       SwiftData per-day task instance
Sources/DailyCore/Models/AppSettings.swift     SwiftData singleton settings
Sources/DailyCore/Persistence/TaskRepository.swift       Persistence protocol
Sources/DailyCore/Persistence/SwiftDataTaskRepository.swift SwiftData implementation
Sources/DailyCore/Services/TaskService.swift             Task CRUD, completion, ordering
Sources/DailyCore/Services/DayRolloverService.swift       Idempotent cross-day generation
Sources/DailyCore/Services/NotificationScheduling.swift  Notification protocol and identifiers
Sources/DailyCore/Services/NotificationService.swift     UserNotifications implementation
Sources/DailyCore/Services/ReminderSettingsService.swift Reminder settings and permission workflow
Sources/DailyCore/Support/DayProviding.swift             Injectable clock/calendar boundary
Sources/DailyApp/App/DailyApp.swift            App entry, WindowGroup, MenuBarExtra
Sources/DailyApp/App/AppDependencies.swift     Model container and production services
Sources/DailyApp/App/AppModel.swift            Shared observable UI state and commands
Sources/DailyApp/Design/MotionTokens.swift     Spring and accessibility-aware motion tokens
Sources/DailyApp/Design/GlassModule.swift      Shared native glass module modifier
Sources/DailyApp/Features/Shell/AppShellView.swift        Main NavigationSplitView
Sources/DailyApp/Features/Shell/SidebarView.swift         Today/rules/history/settings navigation
Sources/DailyApp/Features/Today/TodayView.swift           Unified list and progress
Sources/DailyApp/Features/Today/TaskRow.swift             Glass task row and completion control
Sources/DailyApp/Features/Today/ReorderableTaskList.swift Direct-manipulation drag ordering
Sources/DailyApp/Features/Today/QuickAddView.swift        Inline quick add
Sources/DailyApp/Features/Today/TaskEditorView.swift      One-time/recurrence/reminder editor
Sources/DailyApp/Features/Rules/RulesView.swift           Recurring template management
Sources/DailyApp/Features/History/HistoryView.swift       Weekly completion summary and day detail
Sources/DailyApp/Features/Settings/SettingsView.swift     Reminder and permission settings
Sources/DailyApp/Features/MenuBar/MenuBarContentView.swift Compact shared daily list
Sources/DailyApp/Resources/Info.plist          App identity and UI agent configuration
scripts/build-app.sh                           Build, bundle, and ad-hoc sign Daily.app
Tests/DailyCoreTests/...                       Domain, repository, task, rollover, notification tests
Tests/DailyAppTests/AppModelTests.swift        Shared-state integration tests
```

### Task 1: Bootstrap a testable macOS application package

**Files:**
- Create: `Package.swift`
- Create: `Sources/DailyCore/Domain/LocalDay.swift`
- Create: `Sources/DailyApp/App/DailyApp.swift`
- Create: `Tests/DailyCoreTests/LocalDayTests.swift`

**Interfaces:**
- Produces: `LocalDay`, `LocalDay.init(date:calendar:)`, `LocalDay.date(in:)`, and SwiftPM modules `DailyCore` and `DailyApp`.

- [ ] **Step 1: Write the failing local-day test**

```swift
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
```

- [ ] **Step 2: Create the package manifest and verify the test fails**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Daily",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DailyCore", targets: ["DailyCore"]),
        .executable(name: "Daily", targets: ["DailyApp"])
    ],
    targets: [
        .target(name: "DailyCore"),
        .executableTarget(name: "DailyApp", dependencies: ["DailyCore"], exclude: ["Resources"]),
        .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"]),
        .testTarget(name: "DailyAppTests", dependencies: ["DailyApp", "DailyCore"])
    ]
)
```

Run: `swift test --filter LocalDayTests`

Expected: FAIL because `LocalDay` is undefined.

- [ ] **Step 3: Implement `LocalDay`**

```swift
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
```

- [ ] **Step 4: Add the temporary app entry and run the package tests**

```swift
import SwiftUI

@main
struct DailyApp: App {
    var body: some Scene {
        WindowGroup { Text("Daily") }
    }
}
```

Run: `swift test && swift build`

Expected: all tests PASS and the executable builds for macOS 26.

- [ ] **Step 5: Commit the bootstrap**

```bash
git add Package.swift Sources Tests
git commit -m "chore: bootstrap Daily macOS package"
```

### Task 2: Define recurrence, reminder, and SwiftData models

**Files:**
- Create: `Sources/DailyCore/Domain/TaskTypes.swift`
- Create: `Sources/DailyCore/Models/TaskTemplate.swift`
- Create: `Sources/DailyCore/Models/DailyTask.swift`
- Create: `Sources/DailyCore/Models/AppSettings.swift`
- Create: `Tests/DailyCoreTests/RecurrenceRuleTests.swift`

**Interfaces:**
- Produces: `TaskKind`, `ReminderMode`, `RecurrenceRule`, `TaskDraft`, `DeleteScope`, `HistoryStatus`, `TaskTemplate`, `DailyTask`, and `AppSettings`.
- `RecurrenceRule.matches(_:calendar:) -> Bool` is consumed by `DayRolloverService`.

- [ ] **Step 1: Write failing recurrence tests**

```swift
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
```

- [ ] **Step 2: Run tests and verify the missing types fail**

Run: `swift test --filter RecurrenceRuleTests`

Expected: FAIL because `RecurrenceRule` and related types do not exist.

- [ ] **Step 3: Implement domain types and matching**

```swift
public enum TaskKind: String, Codable, Sendable { case once, recurring }
public enum ReminderMode: String, Codable, Sendable { case none, once, persistent }
public enum RecurrenceFrequency: String, Codable, Sendable { case daily, weekdays, selectedWeekdays }
public enum DeleteScope: Sendable { case todayOnly, allFuture }
public enum HistoryStatus: Equatable, Sendable { case completed, incomplete, rolledOver }

public struct RecurrenceRule: Codable, Equatable, Sendable {
    public var frequency: RecurrenceFrequency
    public var weekdays: Set<Int>
    public var startDay: LocalDay

    public func matches(_ day: LocalDay, calendar: Calendar) -> Bool {
        guard day >= startDay else { return false }
        let weekday = calendar.component(.weekday, from: day.date(in: calendar))
        switch frequency {
        case .daily: return true
        case .weekdays: return (2...6).contains(weekday)
        case .selectedWeekdays: return weekdays.contains(weekday)
        }
    }
}

public struct TaskDraft: Sendable {
    public var title: String
    public var kind: TaskKind
    public var recurrence: RecurrenceRule?
    public var reminderMode: ReminderMode
    public var reminderHour: Int?
    public var reminderMinute: Int?

    public init(
        title: String,
        kind: TaskKind = .once,
        recurrence: RecurrenceRule? = nil,
        reminderMode: ReminderMode = .none,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.title = title
        self.kind = kind
        self.recurrence = recurrence
        self.reminderMode = reminderMode
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}
```

Add explicit `public` initializers for `RecurrenceRule`, every model, and every domain value used by `DailyApp`; Swift's synthesized memberwise initializers are not public across targets.

- [ ] **Step 4: Add the three SwiftData models with explicit stored fields**

`TaskTemplate` fields: unique `id`, `title`, `kindRaw`, optional `recurrenceData`, `reminderModeRaw`, optional `reminderHour`, optional `reminderMinute`, `sortIndex`, `isEnabled`, `createdAt`, and `updatedAt`.

`DailyTask` fields: unique `id`, `templateID`, `dayKey`, `titleSnapshot`, `reminderModeRaw`, optional `reminderHour`, optional `reminderMinute`, `sortIndex`, optional `completedAt`, optional `rolloverOriginID`, `originalDayKey`, `rolloverCount`, and `createdAt`.

`AppSettings` fields: unique `id`, `dailyReminderEnabled`, optional `dailyReminderHour`, optional `dailyReminderMinute`, `persistentIntervalMinutes`, and optional `lastProcessedDayKey`. Give it `static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!` and defaults of disabled daily reminder and 15 minutes.

For encoded recurrence, expose computed properties rather than leaking raw strings or `Data`:

```swift
public var kind: TaskKind {
    get { TaskKind(rawValue: kindRaw)! }
    set { kindRaw = newValue.rawValue }
}

public var recurrence: RecurrenceRule? {
    get { recurrenceData.flatMap { try? JSONDecoder().decode(RecurrenceRule.self, from: $0) } }
    set { recurrenceData = try? newValue.map { try JSONEncoder().encode($0) } }
}
```

- [ ] **Step 5: Run model and recurrence tests**

Run: `swift test --filter RecurrenceRuleTests && swift test`

Expected: all tests PASS.

- [ ] **Step 6: Commit the domain model**

```bash
git add Sources/DailyCore Tests/DailyCoreTests/RecurrenceRuleTests.swift
git commit -m "feat: add task domain and persistence models"
```

### Task 3: Add repository boundaries and SwiftData persistence

**Files:**
- Create: `Sources/DailyCore/Persistence/TaskRepository.swift`
- Create: `Sources/DailyCore/Persistence/SwiftDataTaskRepository.swift`
- Create: `Tests/DailyCoreTests/SwiftDataTaskRepositoryTests.swift`

**Interfaces:**
- Consumes: `TaskTemplate`, `DailyTask`, `AppSettings`, and `LocalDay`.
- Produces: `@MainActor TaskRepository` with the exact methods below and `SwiftDataTaskRepository.init(context:)`.

```swift
@MainActor
public protocol TaskRepository: AnyObject {
    func templates(enabledOnly: Bool) throws -> [TaskTemplate]
    func template(id: UUID) throws -> TaskTemplate?
    func dailyTasks(on day: LocalDay) throws -> [DailyTask]
    func dailyTasks(from start: LocalDay, through end: LocalDay) throws -> [DailyTask]
    func dailyTask(id: UUID) throws -> DailyTask?
    func insert(_ template: TaskTemplate)
    func insert(_ task: DailyTask)
    func remove(_ task: DailyTask)
    func settings() throws -> AppSettings
    func save() throws
}
```

- [ ] **Step 1: Write failing in-memory SwiftData tests**

Test that `settings()` creates exactly one singleton, `dailyTasks(on:)` filters by `dayKey` and sorts by `sortIndex`, and `templates(enabledOnly: true)` omits disabled templates. Use:

```swift
let schema = Schema([TaskTemplate.self, DailyTask.self, AppSettings.self])
let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: configuration)
let repository = SwiftDataTaskRepository(context: container.mainContext)
```

- [ ] **Step 2: Run repository tests and verify failure**

Run: `swift test --filter SwiftDataTaskRepositoryTests`

Expected: FAIL because the repository protocol and implementation are missing.

- [ ] **Step 3: Implement fetch descriptors and singleton settings**

Use `FetchDescriptor` predicates on `dayKey`, `id`, and `isEnabled`; use `SortDescriptor(\.sortIndex)` for list order. `settings()` fetches `AppSettings.singletonID`, inserts a default model if absent, saves, and returns it. Do not expose `ModelContext` outside this file.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter SwiftDataTaskRepositoryTests && swift test`

Expected: all tests PASS.

- [ ] **Step 5: Commit persistence**

```bash
git add Sources/DailyCore/Persistence Tests/DailyCoreTests/SwiftDataTaskRepositoryTests.swift
git commit -m "feat: add SwiftData task repository"
```

### Task 4: Implement task creation, completion, deletion, and ordering

**Files:**
- Create: `Sources/DailyCore/Services/NotificationScheduling.swift`
- Create: `Sources/DailyCore/Services/TaskService.swift`
- Create: `Tests/DailyCoreTests/TaskServiceTests.swift`
- Create: `Tests/DailyCoreTests/TestDoubles.swift`

**Interfaces:**
- Consumes: `TaskRepository`, domain types, and `NotificationScheduling`.
- Produces:

```swift
@MainActor
public protocol NotificationScheduling: AnyObject {
    func sync(task: DailyTask, persistentIntervalMinutes: Int, now: Date) async throws
    func cancel(taskID: UUID) async
    func syncDailyReminder(settings: AppSettings, now: Date) async throws
    func rebuild(tasks: [DailyTask], settings: AppSettings, now: Date) async throws
}

public enum TaskServiceError: Error, Equatable {
    case emptyTitle
    case recurrenceRequired
    case taskNotFound
    case templateNotFound
    case notificationSyncFailed
}

@MainActor
public final class TaskService {
    public init(repository: TaskRepository, notifications: NotificationScheduling)
    public func today(on day: LocalDay) throws -> [DailyTask]
    public func recurringTemplates() throws -> [TaskTemplate]
    public func create(_ draft: TaskDraft, on day: LocalDay, now: Date) async throws -> DailyTask
    public func update(templateID: UUID, draft: TaskDraft, on day: LocalDay, now: Date) async throws
    public func setCompleted(id: UUID, completed: Bool, at date: Date) async throws
    public func setTemplateEnabled(id: UUID, enabled: Bool) throws
    public func reorder(ids: [UUID]) throws
    public func delete(id: UUID, scope: DeleteScope) async throws
}
```

- [ ] **Step 1: Add test doubles and failing service tests**

`TestTaskRepository` stores templates/tasks/settings in arrays. `RecordingNotificationScheduler` records synced and cancelled task IDs. Tests must prove:

- Blank titles throw `TaskServiceError.emptyTitle` without inserting.
- Creation trims the title, creates one template and one current-day instance, and schedules its reminder with the stored global interval.
- Updating a template changes today's incomplete snapshot and future source data, but preserves an already completed snapshot.
- Completing sets `completedAt`, disables a one-time template, and cancels notifications.
- Uncompleting clears `completedAt`, re-enables a one-time template, and reschedules.
- `reorder(ids:)` assigns `0, 1000, 2000...` in the supplied order.
- `delete(.todayOnly)` removes only the instance.
- `delete(.allFuture)` removes the current instance, disables its template, and cancels notifications.

- [ ] **Step 2: Verify focused tests fail**

Run: `swift test --filter TaskServiceTests`

Expected: FAIL because `TaskService` is missing.

- [ ] **Step 3: Implement create and query**

Validate `draft.title.trimmingCharacters(in: .whitespacesAndNewlines)`. Require a recurrence when `kind == .recurring`, persist a `TaskTemplate`, copy title/reminder values to a `DailyTask`, assign the next sort index as `(currentMax ?? -1000) + 1000`, save, fetch `repository.settings().persistentIntervalMinutes`, then call `notifications.sync(task:persistentIntervalMinutes:now:)`.

- [ ] **Step 4: Implement completion, reorder, and deletion**

Persist before notification work. If notification synchronization fails, keep task data committed and rethrow `TaskServiceError.notificationSyncFailed`; this lets the UI show a retry banner without losing edits.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter TaskServiceTests && swift test`

Expected: all tests PASS.

- [ ] **Step 6: Commit task behavior**

```bash
git add Sources/DailyCore/Services Tests/DailyCoreTests
git commit -m "feat: implement daily task operations"
```

### Task 5: Implement idempotent rollover and history states

**Files:**
- Create: `Sources/DailyCore/Support/DayProviding.swift`
- Create: `Sources/DailyCore/Services/DayRolloverService.swift`
- Create: `Tests/DailyCoreTests/DayRolloverServiceTests.swift`

**Interfaces:**
- Consumes: `TaskRepository`, `NotificationScheduling`, `RecurrenceRule.matches`, and `AppSettings.lastProcessedDayKey`.
- Produces:

```swift
public protocol DayProviding: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
}

@MainActor
public final class DayRolloverService {
    public init(repository: TaskRepository, notifications: NotificationScheduling, dayProvider: DayProviding)
    public func processThroughToday() async throws
    public func historyStatus(for task: DailyTask, allTasks: [DailyTask]) -> HistoryStatus
}
```

- [ ] **Step 1: Write failing rollover tests**

Cover these exact scenarios:

1. Calling `processThroughToday()` twice produces no duplicate `templateID + dayKey` instances.
2. An incomplete one-time task creates one child per missed day, marks intermediate history as `.rolledOver`, and exposes only today's child as current.
3. An incomplete recurring task creates the next matching day's new instance but no rollover child.
4. A disabled template generates no future instance.
5. A weekly rule skips nonmatching days.
6. After success, `lastProcessedDayKey` equals today.
7. A notification rebuild runs once with today's incomplete tasks.

- [ ] **Step 2: Verify rollover tests fail**

Run: `swift test --filter DayRolloverServiceTests`

Expected: FAIL because rollover behavior is missing.

- [ ] **Step 3: Implement day-by-day processing**

Starting at the day after `lastProcessedDayKey` and ending at today, process each date in order. Before inserting, index existing instances by `templateID + dayKey`. For each prior-day incomplete one-time task, insert the next-day child with `rolloverOriginID`, original day, and incremented count. For each enabled recurring template whose rule matches, insert a fresh snapshot only if the logical key is absent.

- [ ] **Step 4: Implement history status and final notification rebuild**

Return `.completed` when `completedAt != nil`; `.rolledOver` when another task has `rolloverOriginID == task.id`; otherwise return `.incomplete`. Save `lastProcessedDayKey` after every fully processed day so a crash resumes safely. Rebuild notifications only after all dates are processed.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter DayRolloverServiceTests && swift test`

Expected: all tests PASS.

- [ ] **Step 6: Commit rollover**

```bash
git add Sources/DailyCore/Support Sources/DailyCore/Services/DayRolloverService.swift Tests/DailyCoreTests/DayRolloverServiceTests.swift
git commit -m "feat: add idempotent daily rollover"
```

### Task 6: Implement local notification scheduling

**Files:**
- Create: `Sources/DailyCore/Services/NotificationService.swift`
- Create: `Sources/DailyCore/Services/ReminderSettingsService.swift`
- Create: `Tests/DailyCoreTests/NotificationServiceTests.swift`

**Interfaces:**
- Consumes: `NotificationScheduling`, `DailyTask`, `AppSettings`, and injected notification-center adapter.
- Produces: `NotificationService`, `NotificationCenterClient`, and deterministic identifiers.

```swift
public protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(ids: [String])
    func pendingRequests() async -> [UNNotificationRequest]
}

@MainActor
public final class ReminderSettingsService {
    public init(repository: TaskRepository, notifications: NotificationScheduling)
    public func settings() throws -> AppSettings
    public func updateDailyReminder(enabled: Bool, hour: Int?, minute: Int?, now: Date) async throws
    public func updatePersistentInterval(minutes: Int) throws
}

public enum NotificationID {
    public static let daily = "daily.summary"
    public static func task(_ id: UUID, sequence: Int) -> String { "task.\(id.uuidString).\(sequence)" }
}
```

- [ ] **Step 1: Write failing notification tests with a recording center**

Test that:

- `.none` creates no request.
- `.once` creates one calendar trigger only when its time is in the future.
- `.persistent` created after its nominal time starts at `now + interval`.
- `.persistent` creates exactly eight requests at the configured interval.
- Cancelling a task removes all identifiers with its prefix.
- Daily reminder uses `daily.summary`; disabling it removes the old request.
- Rebuild removes stale `task.` requests and schedules only incomplete current tasks.
- Settings reject intervals outside `5, 10, 15, 30, 60` and synchronize daily reminder changes after saving.

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter NotificationServiceTests`

Expected: FAIL because `NotificationService` is missing.

- [ ] **Step 3: Implement authorization and trigger calculation**

Use `UNCalendarNotificationTrigger` for future same-day times and `UNTimeIntervalNotificationTrigger` for persistent follow-ups. Create notification content with task title, sound `.default`, and category identifier `TASK_REMINDER`. The daily summary body is `查看今天的任务并开始行动。`.

- [ ] **Step 4: Implement eight-request rolling windows and cancellation**

Before syncing one task, fetch pending requests, remove every identifier beginning with `task.<UUID>.`, and then schedule the new window. Use the `persistentIntervalMinutes` argument for spacing. Never request authorization during background rollover; expose permission request as an explicit settings action.

- [ ] **Step 5: Implement reminder settings service**

`updateDailyReminder` validates that enabled reminders have hour `0...23` and minute `0...59`, saves the singleton settings, then calls `syncDailyReminder`. `updatePersistentInterval` accepts only `5, 10, 15, 30, 60`. Define explicit `ReminderSettingsError.invalidTime`, `.invalidInterval`, and `.notificationSyncFailed` cases.

- [ ] **Step 6: Run focused and full tests**

Run: `swift test --filter NotificationServiceTests && swift test`

Expected: all tests PASS.

- [ ] **Step 7: Commit notifications**

```bash
git add Sources/DailyCore/Services/NotificationService.swift Sources/DailyCore/Services/ReminderSettingsService.swift Tests/DailyCoreTests/NotificationServiceTests.swift
git commit -m "feat: schedule local task reminders"
```

### Task 7: Build the shared observable application model

**Files:**
- Create: `Sources/DailyApp/App/AppDependencies.swift`
- Create: `Sources/DailyApp/App/AppModel.swift`
- Create: `Tests/DailyAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `TaskService`, `DayRolloverService`, `ReminderSettingsService`, `TaskRepository`, `DayProviding`, and notification permission APIs.
- Produces UI state and commands:

```swift
@MainActor @Observable
final class AppModel {
    enum Destination: Hashable { case today, rules, history, settings }
    private(set) var todayTasks: [DailyTask] = []
    private(set) var templates: [TaskTemplate] = []
    private(set) var selectedHistoryDay: LocalDay
    private(set) var errorMessage: String?
    private(set) var lastCompletionUndo: (taskID: UUID, wasCompleted: Bool)?
    var destination: Destination = .today
    var editorTaskID: UUID?
    var isPresentingNewTask = false

    var completedCount: Int { todayTasks.lazy.filter { $0.completedAt != nil }.count }
    var completionFraction: Double { todayTasks.isEmpty ? 0 : Double(completedCount) / Double(todayTasks.count) }

    func start() async
    func reload() throws
    func add(_ draft: TaskDraft) async
    func toggle(_ task: DailyTask) async
    func undoLastCompletion() async
    func delete(_ task: DailyTask, scope: DeleteScope) async
    func reorder(ids: [UUID])
    func clearError()
}
```

- [ ] **Step 1: Write failing shared-state tests**

Test zero-task completion fraction, two-of-four completion, add reloads state, toggle updates both count and task state, undo restores the previous completion state, failures populate `errorMessage`, and two consumers holding the same `AppModel` observe identical arrays.

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter AppModelTests`

Expected: FAIL because `AppModel` is missing.

- [ ] **Step 3: Implement dependencies and startup**

`AppDependencies.live()` creates one `ModelContainer` using the three SwiftData models, one repository, services, and one `AppModel`. `start()` calls rollover and then reload. Register observers for calendar-day, system-clock, time-zone, wake, and app activation changes; every callback runs rollover followed by reload.

- [ ] **Step 4: Implement commands and recoverable errors**

Every command calls the matching service and then `reload()`. On failure, preserve the current list and assign a specific Chinese message such as `任务已保存，但提醒未能安排。请重试。`; do not silently discard errors.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter AppModelTests && swift test`

Expected: all tests PASS.

- [ ] **Step 6: Commit shared state**

```bash
git add Sources/DailyApp/App Tests/DailyAppTests
git commit -m "feat: add shared application model"
```

### Task 8: Implement monochrome Liquid Glass design primitives and Today UI

**Files:**
- Create: `Sources/DailyApp/Design/MotionTokens.swift`
- Create: `Sources/DailyApp/Design/GlassModule.swift`
- Create: `Sources/DailyApp/Features/Shell/AppShellView.swift`
- Create: `Sources/DailyApp/Features/Shell/SidebarView.swift`
- Create: `Sources/DailyApp/Features/Today/TodayView.swift`
- Create: `Sources/DailyApp/Features/Today/TaskRow.swift`
- Create: `Sources/DailyApp/Features/Today/ReorderableTaskList.swift`
- Create: `Sources/DailyApp/Features/Today/QuickAddView.swift`
- Create: `Sources/DailyApp/Features/Today/TaskEditorView.swift`

**Interfaces:**
- Consumes: shared `AppModel`, `TaskDraft`, `DailyTask`, and macOS accessibility environment values.
- Produces: the main TickTick-inspired sidebar/list workflow and reusable glass/motion primitives.

- [ ] **Step 1: Add a compile-time smoke test for design tokens**

Create an `AppModelTests` assertion that `MotionTokens.pressScale == 0.97`, normal motion has no bounce, physical motion has light bounce, and reduced motion returns no displacement. This is a value-level test, not a screenshot test.

- [ ] **Step 2: Verify the design-token test fails**

Run: `swift test --filter AppModelTests`

Expected: FAIL because `MotionTokens` is missing.

- [ ] **Step 3: Implement motion and glass primitives**

```swift
enum MotionTokens {
    static let pressScale = 0.97
    static let hoverLift: CGFloat = -2
    static let standard = Animation.spring(duration: 0.36, bounce: 0)
    static let physical = Animation.spring(duration: 0.36, bounce: 0.18)
}

struct GlassModule: ViewModifier {
    var interactive = true
    var shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    func body(content: Content) -> some View {
        content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}
```

Extend the modifier to read `accessibilityReduceTransparency`, `accessibilityReduceMotion`, and `colorSchemeContrast`. With reduced transparency, render an opaque system background plus a high-contrast stroke instead of glass.

- [ ] **Step 4: Implement the shell and unified Today list**

Use `NavigationSplitView` with destinations 今日、重复规则、历史记录、设置. `TodayView` renders date, `completedCount / total`, monochrome progress, one `ForEach` over `todayTasks`, and `QuickAddView`; do not add sections for task origin. Wrap adjacent task rows in one `GlassEffectContainer`.

- [ ] **Step 5: Implement task interaction and editor**

`TaskRow` provides checkbox, title, optional reminder time, optional `已顺延 N 天`, hover lift, press scale, keyboard focus outline, VoiceOver labels, and drag handle. Completion animates the checkmark, title, glass state, and progress with one transaction, then shows a five-second `撤销` overlay wired to `undoLastCompletion()`. `TaskEditorView` exposes title, only-today/repeating, daily/weekdays/selected weekdays, reminder mode, and time; default is only today with no reminder.

`ReorderableTaskList` uses `DragGesture(minimumDistance: 6)`, stores the grab offset, renders the active row in an overlay that follows translation 1:1, offsets neighboring rows continuously, and calls `AppModel.reorder(ids:)` only after the projected destination changes. On release, pass `predictedEndTranslation` into `MotionTokens.physical`; when Reduce Motion is enabled, skip projection and reorder immediately. The active gesture remains enabled while the settling animation runs so a new drag can interrupt it.

- [ ] **Step 6: Build and manually inspect the main window**

Run: `swift test && swift build && swift run Daily`

Expected: a main window opens with a monochrome sidebar and unified glass task list; adding and completing tasks update progress without restarting.

- [ ] **Step 7: Commit Today UI**

```bash
git add Sources/DailyApp/Design Sources/DailyApp/Features/Shell Sources/DailyApp/Features/Today Tests/DailyAppTests
git commit -m "feat: build Liquid Glass today experience"
```

### Task 9: Implement recurrence, history, and settings screens

**Files:**
- Create: `Sources/DailyApp/Features/Rules/RulesView.swift`
- Create: `Sources/DailyApp/Features/History/HistoryView.swift`
- Create: `Sources/DailyApp/Features/Settings/SettingsView.swift`
- Modify: `Sources/DailyApp/App/AppModel.swift`
- Modify: `Sources/DailyApp/Features/Shell/AppShellView.swift`
- Create: `Tests/DailyAppTests/HistoryPresentationTests.swift`

**Interfaces:**
- Consumes: repository history queries, rollover history status, settings, and task editor.
- Produces: `HistoryDaySummary`, `AppModel.history(weekContaining:)`, template enable/edit/delete actions, and permission settings actions.

- [ ] **Step 1: Write failing history presentation tests**

Test that a day with two completed tasks, one incomplete recurring task, and one rolled-over one-time task yields total `4`, completed `2`, fraction `0.5`, and the three correct statuses. Test that an empty day has `completionFraction == nil`, not zero percent.

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter HistoryPresentationTests`

Expected: FAIL because history summaries are missing.

- [ ] **Step 3: Implement history summaries and weekly UI**

Add:

```swift
struct HistoryDaySummary: Identifiable {
    let day: LocalDay
    let tasks: [(DailyTask, HistoryStatus)]
    var id: String { day.rawValue }
    var completedCount: Int { tasks.filter { $0.1 == .completed }.count }
    var completionFraction: Double? { tasks.isEmpty ? nil : Double(completedCount) / Double(tasks.count) }
}
```

Render seven compact day cells and a read-only task detail list. Use monochrome intensity for completion levels; include text counts so color is never the only signal.

- [ ] **Step 4: Implement recurring-template management**

List enabled and disabled templates, allow drag reorder, edit in `TaskEditorView`, toggle `isEnabled`, and delete without touching historical `DailyTask` records. From the Today row, repeated deletion offers `仅移除今天` and `停止以后重复`; only the latter asks for confirmation.

- [ ] **Step 5: Implement settings and permission flow**

Expose daily reminder enable/time, persistent interval choices `5, 10, 15, 30, 60`, current authorization status, a one-time authorization button, and an `x-apple.systempreferences:com.apple.preference.notifications` link when denied. Saving settings calls `syncDailyReminder` and surfaces scheduling errors.

- [ ] **Step 6: Run tests and inspect all destinations**

Run: `swift test && swift run Daily`

Expected: Rules, History, and Settings navigate correctly; history is read-only; settings persist after relaunch.

- [ ] **Step 7: Commit supporting screens**

```bash
git add Sources/DailyApp/Features Sources/DailyApp/App/AppModel.swift Tests/DailyAppTests/HistoryPresentationTests.swift
git commit -m "feat: add rules history and settings screens"
```

### Task 10: Add the shared menu-bar panel, shortcuts, and lifecycle hooks

**Files:**
- Create: `Sources/DailyApp/Features/MenuBar/MenuBarContentView.swift`
- Modify: `Sources/DailyApp/App/DailyApp.swift`
- Modify: `Sources/DailyApp/App/AppModel.swift`
- Create: `Tests/DailyAppTests/MenuBarStateTests.swift`

**Interfaces:**
- Consumes: the same `AppModel` instance injected into `WindowGroup`.
- Produces: `MenuBarExtra`, in-app quick-add command `Command+Shift+A`, destination shortcuts `Command+1...4`, and app-activation rollover.

- [ ] **Step 1: Write the failing shared-instance test**

Construct one `AppModel`, pass it to two lightweight test consumers representing window and menu bar, toggle a task through one consumer, and assert the other sees the same completed count and task ID.

- [ ] **Step 2: Verify the test fails before wiring the scene**

Run: `swift test --filter MenuBarStateTests`

Expected: FAIL until the scene/dependency factory exposes one shared instance.

- [ ] **Step 3: Implement both scenes with one model**

```swift
@main
struct DailyApp: App {
    @State private var model = AppDependencies.live().appModel

    var body: some Scene {
        WindowGroup { AppShellView().environment(model) }
        MenuBarExtra("Daily", systemImage: "checklist") {
            MenuBarContentView().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
```

`MenuBarContentView` shows count, progress, the same unified task array, completion buttons, quick-add field, and `打开 Daily` using `openWindow`. Do not include rules, history, or advanced reminder controls.

- [ ] **Step 4: Add commands and lifecycle rollover**

Define SwiftUI `Commands` for quick add and Today/Rules/History/Settings navigation. On `scenePhase == .active`, wake notification, calendar-day change, clock change, or time-zone change, call `model.start()`; idempotence prevents duplicate instances. Opening the menu-bar panel remains a direct click on the status item because SwiftUI does not expose a supported command for programmatically opening `MenuBarExtra`.

- [ ] **Step 5: Run tests and manual dual-surface verification**

Run: `swift test && swift run Daily`

Expected: completing or adding a task in either surface updates the other immediately; relaunch and wake preserve correct date state.

- [ ] **Step 6: Commit menu-bar integration**

```bash
git add Sources/DailyApp Tests/DailyAppTests/MenuBarStateTests.swift
git commit -m "feat: add shared menu bar workflow"
```

### Task 11: Package, accessibility-check, and verify the complete app

**Files:**
- Create: `Sources/DailyApp/Resources/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `docs/manual-test-checklist.md`
- Create: `README.md`

**Interfaces:**
- Consumes: release executable and resources.
- Produces: `build/Daily.app` with bundle identifier `com.daily.todo`, ad-hoc signature, and launchable notification identity.

- [ ] **Step 1: Add the app metadata**

Create an `Info.plist` with `CFBundleIdentifier=com.daily.todo`, `CFBundleName=Daily`, `CFBundleDisplayName=Daily`, `CFBundleExecutable=Daily`, `CFBundlePackageType=APPL`, `LSMinimumSystemVersion=26.0`, and `NSPrincipalClass=NSApplication`.

- [ ] **Step 2: Add the deterministic bundle script**

```bash
#!/usr/bin/env bash
set -euo pipefail
swift build -c release
app_dir="build/Daily.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp ".build/release/Daily" "$app_dir/Contents/MacOS/Daily"
cp "Sources/DailyApp/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
```

- [ ] **Step 3: Write the manual verification checklist**

Include exact checks for create/edit/delete/reorder; one-time rollover; recurring generation; eight persistent reminders and cancellation; daily reminder; window/menu synchronization; relaunch persistence; time-zone change; denied notification permission; light/dark mode; hover gloss and refraction; interruptible drag; keyboard-only operation; VoiceOver labels; Reduce Motion; Reduce Transparency; and Increase Contrast.

- [ ] **Step 4: Document build and launch commands**

`README.md` must include prerequisites `macOS 26` and `Xcode 26.6`, then:

```bash
swift test
bash scripts/build-app.sh
open build/Daily.app
```

- [ ] **Step 5: Run complete automated verification**

Run: `swift test && swift build -c release && bash scripts/build-app.sh`

Expected: tests PASS, release build succeeds, `codesign --verify` exits zero, and `build/Daily.app` exists.

- [ ] **Step 6: Run the manual checklist**

Launch `build/Daily.app`. Complete every item in `docs/manual-test-checklist.md`, recording `PASS`, the macOS build, and any failure notes beside each line. Use a notification time two minutes ahead for reminder verification.

- [ ] **Step 7: Commit packaging and verification documentation**

```bash
git add Sources/DailyApp/Resources scripts README.md docs/manual-test-checklist.md
git commit -m "chore: package and verify Daily app"
```

- [ ] **Step 8: Final repository check**

Run: `git status --short && git log --oneline -11`

Expected: clean worktree and one focused commit for each completed task.
