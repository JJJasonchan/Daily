import DailyCore
import Sparkle
import SwiftUI
import UserNotifications

@MainActor
struct SettingsPresentationState {
    var dailyReminderEnabled = false
    var dailyReminderTime = Date.now
    var persistentIntervalMinutes = 15
    private(set) var isHydrated = false
    var colorSchemeMode: ColorSchemeMode = .system

    mutating func hydrate(
        from model: AppModel,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard !isHydrated else { return }
        dailyReminderEnabled = model.dailyReminderEnabled
        colorSchemeMode = model.colorSchemeMode
        persistentIntervalMinutes = Self.intervalChoices.contains(
            model.persistentIntervalMinutes
        ) ? model.persistentIntervalMinutes : 15
        dailyReminderTime = calendar.date(
            from: DateComponents(
                hour: model.dailyReminderHour,
                minute: model.dailyReminderMinute
            )
        ) ?? .now
        isHydrated = true
    }

    static let intervalChoices = [5, 10, 15, 30, 60]
}

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var presentation = SettingsPresentationState()
    @State private var reminderPersistTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("🎨 外观") {
                Picker("颜色模式", selection: colorSchemeBinding) {
                    ForEach(ColorSchemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("🔔 每日提醒") {
                Toggle("启用每日提醒", isOn: reminderEnabledBinding)

                if presentation.dailyReminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: $presentation.dailyReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: presentation.dailyReminderTime) { _, _ in
                        scheduleReminderPersist()
                    }
                }
            }

            Section("⏰ 重复提醒") {
                Picker("重复间隔", selection: persistentIntervalBinding) {
                    ForEach(SettingsPresentationState.intervalChoices, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Text("从任务设定的提醒时间起计算，任务当天最多提醒 \(NotificationService.persistentRequestCount) 次。已过的时刻会跳过，完成后停止提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("🔐 通知权限") {
                LabeledContent("当前状态", value: authorizationDescription)

                if model.notificationAuthorizationStatus == .notDetermined {
                    Button("请求通知权限") {
                        Task { @MainActor in
                            await model.requestNotificationAuthorization()
                        }
                    }
                }

                if model.notificationAuthorizationStatus == .denied,
                   let settingsURL = URL(
                       string: "x-apple.systempreferences:com.apple.preference.notifications"
                   ) {
                    Link("打开系统通知设置", destination: settingsURL)
                }
            }

            Section("🔄 更新") {
                LabeledContent("当前版本", value: currentVersion)
                Toggle("自动检查更新", isOn: Binding(
                    get: { model.updaterController.updater.automaticallyChecksForUpdates },
                    set: { model.updaterController.updater.automaticallyChecksForUpdates = $0 }
                ))
                HStack {
                    Button("检查更新") {
                        model.checkForUpdates()
                    }
                    Spacer()
                }
            }

        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("设置")
        .task {
            model.loadReminderSettings()
            presentation.hydrate(from: model)
            await model.refreshNotificationAuthorizationStatus()
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    private var authorizationDescription: String {
        switch model.notificationAuthorizationStatus {
        case .notDetermined:
            return "尚未请求"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已允许"
        case .provisional:
            return "临时允许"
        case .ephemeral:
            return "临时会话允许"
        @unknown default:
            return "未知"
        }
    }

    private var colorSchemeBinding: Binding<ColorSchemeMode> {
        Binding(
            get: { presentation.colorSchemeMode },
            set: { newValue in
                presentation.colorSchemeMode = newValue
                model.saveColorSchemeMode(newValue)
            }
        )
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { presentation.dailyReminderEnabled },
            set: { newValue in
                presentation.dailyReminderEnabled = newValue
                persistReminderSettings()
            }
        )
    }

    private var persistentIntervalBinding: Binding<Int> {
        Binding(
            get: { presentation.persistentIntervalMinutes },
            set: { newValue in
                presentation.persistentIntervalMinutes = newValue
                persistReminderSettings()
            }
        )
    }

    private func persistReminderSettings() {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: presentation.dailyReminderTime
        )
        let enabled = presentation.dailyReminderEnabled
        Task { @MainActor in
            _ = await model.saveReminderSettings(
                enabled: enabled,
                hour: enabled ? components.hour : nil,
                minute: enabled ? components.minute : nil,
                persistentIntervalMinutes: presentation.persistentIntervalMinutes
            )
        }
    }

    private func scheduleReminderPersist() {
        reminderPersistTask?.cancel()
        reminderPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persistReminderSettings()
        }
    }
}
