import DailyCore
import Foundation
import Sparkle
import SwiftData

struct SystemDayProvider: DayProviding {
    var now: Date { .now }
    var calendar: Calendar { .autoupdatingCurrent }
}

struct StoreLocationResolver {
    let bundleIdentifier: String
    let applicationSupportRoot: URL

    var directoryURL: URL {
        applicationSupportRoot.appending(
            path: bundleIdentifier,
            directoryHint: .isDirectory
        )
    }

    var storeURL: URL {
        directoryURL.appending(path: "Daily.store", directoryHint: .notDirectory)
    }

    func prepareDirectory(fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    static func live(fileManager: FileManager = .default) throws -> StoreLocationResolver {
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return StoreLocationResolver(
            bundleIdentifier: "com.daily.todo",
            applicationSupportRoot: root
        )
    }
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
    let updaterController: SPUStandardUpdaterController

    private init(
        modelContainer: ModelContainer,
        repository: SwiftDataTaskRepository,
        notificationService: NotificationService,
        taskService: TaskService,
        rolloverService: DayRolloverService,
        reminderSettingsService: ReminderSettingsService,
        appModel: AppModel,
        updaterController: SPUStandardUpdaterController
    ) {
        self.modelContainer = modelContainer
        self.repository = repository
        self.notificationService = notificationService
        self.taskService = taskService
        self.rolloverService = rolloverService
        self.reminderSettingsService = reminderSettingsService
        self.appModel = appModel
        self.updaterController = updaterController
    }

    static func live() -> AppDependencies {
        do {
            let storeLocation = try StoreLocationResolver.live()
            try storeLocation.prepareDirectory(fileManager: .default)
            let configuration = ModelConfiguration(url: storeLocation.storeURL)
            let modelContainer = try ModelContainer(
                for: TaskTemplate.self,
                DailyTask.self,
                AppSettings.self,
                configurations: configuration
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
            let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            let appModel = AppModel(
                taskService: taskService,
                rolloverService: rolloverService,
                reminderSettingsService: reminderSettingsService,
                repository: repository,
                dayProvider: dayProvider,
                notificationService: notificationService,
                lifetimeAnchor: modelContainer,
                updaterController: updaterController
            )
            return AppDependencies(
                modelContainer: modelContainer,
                repository: repository,
                notificationService: notificationService,
                taskService: taskService,
                rolloverService: rolloverService,
                reminderSettingsService: reminderSettingsService,
                appModel: appModel,
                updaterController: updaterController
            )
        } catch {
            fatalError("无法创建 Daily 数据容器：\(error.localizedDescription)")
        }
    }
}
