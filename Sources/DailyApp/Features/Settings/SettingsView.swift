import DailyCore
import SwiftUI
import UserNotifications

@MainActor
struct SettingsPresentationState {
    var dailyReminderEnabled = false
    var dailyReminderTime = Date.now
    var persistentIntervalMinutes = 15
    private(set) var isHydrated = false

    mutating func hydrate(
        from model: AppModel,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard !isHydrated else { return }
        dailyReminderEnabled = model.dailyReminderEnabled
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
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("每日提醒") {
                Toggle("启用每日提醒", isOn: $presentation.dailyReminderEnabled)

                if presentation.dailyReminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: $presentation.dailyReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("持续提醒") {
                Picker("重复间隔", selection: $presentation.persistentIntervalMinutes) {
                    ForEach(SettingsPresentationState.intervalChoices, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Text("用于任务选择“持续提醒”时的再次提醒间隔。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通知权限") {
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

            Section {
                HStack {
                    Spacer()
                    Button("保存设置", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
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

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: presentation.dailyReminderTime
        )

        Task { @MainActor in
            _ = await model.saveReminderSettings(
                enabled: presentation.dailyReminderEnabled,
                hour: presentation.dailyReminderEnabled ? components.hour : nil,
                minute: presentation.dailyReminderEnabled ? components.minute : nil,
                persistentIntervalMinutes: presentation.persistentIntervalMinutes
            )
            isSaving = false
        }
    }
}
