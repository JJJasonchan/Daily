import DailyCore
import Foundation
import SwiftData

struct SystemDayProvider: DayProviding {
    var now: Date { .now }
    var calendar: Calendar { .autoupdatingCurrent }
}

@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let repository: SwiftDataTaskRepository
    let notificationService: NotificationService
    let taskService: TaskService
    let rolloverService: DayRolloverService
    let reminderSettingsService: ReminderSettingsService
    let appModel: AppModel

    private init(
        modelContainer: ModelContainer,
        repository: SwiftDataTaskRepository,
        notificationService: NotificationService,
        taskService: TaskService,
        rolloverService: DayRolloverService,
        reminderSettingsService: ReminderSettingsService,
        appModel: AppModel
    ) {
        self.modelContainer = modelContainer
        self.repository = repository
        self.notificationService = notificationService
        self.taskService = taskService
        self.rolloverService = rolloverService
        self.reminderSettingsService = reminderSettingsService
        self.appModel = appModel
    }

    static func live() -> AppDependencies {
        do {
            let modelContainer = try ModelContainer(
                for: TaskTemplate.self,
                DailyTask.self,
                AppSettings.self
            )
            let repository = SwiftDataTaskRepository(context: modelContainer.mainContext)
            let dayProvider = SystemDayProvider()
            let notificationService = NotificationService(
                center: UserNotificationCenterClient(),
                calendar: dayProvider.calendar
            )
            let taskService = TaskService(
                repository: repository,
                notifications: notificationService
            )
            let rolloverService = DayRolloverService(
                repository: repository,
                notifications: notificationService,
                dayProvider: dayProvider
            )
            let reminderSettingsService = ReminderSettingsService(
                repository: repository,
                notifications: notificationService
            )
            let appModel = AppModel(
                taskService: taskService,
                rolloverService: rolloverService,
                reminderSettingsService: reminderSettingsService,
                repository: repository,
                dayProvider: dayProvider,
                notificationService: notificationService,
                lifetimeAnchor: modelContainer
            )
            return AppDependencies(
                modelContainer: modelContainer,
                repository: repository,
                notificationService: notificationService,
                taskService: taskService,
                rolloverService: rolloverService,
                reminderSettingsService: reminderSettingsService,
                appModel: appModel
            )
        } catch {
            fatalError("无法创建 Daily 数据容器：\(error.localizedDescription)")
        }
    }
}
