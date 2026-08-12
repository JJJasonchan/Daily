import DailyCore
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var dailyReminderEnabled = false
    @State private var dailyReminderTime = Date.now
    @State private var persistentIntervalMinutes = 15
    @State private var isSaving = false

    private let intervalChoices = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section("每日提醒") {
                Toggle("启用每日提醒", isOn: $dailyReminderEnabled)

                if dailyReminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: $dailyReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("持续提醒") {
                Picker("重复间隔", selection: $persistentIntervalMinutes) {
                    ForEach(intervalChoices, id: \.self) { minutes in
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
            await model.loadReminderSettings()
            hydrateForm()
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

    private func hydrateForm() {
        dailyReminderEnabled = model.dailyReminderEnabled
        persistentIntervalMinutes = intervalChoices.contains(model.persistentIntervalMinutes)
            ? model.persistentIntervalMinutes
            : 15
        dailyReminderTime = Calendar.autoupdatingCurrent.date(
            from: DateComponents(
                hour: model.dailyReminderHour,
                minute: model.dailyReminderMinute
            )
        ) ?? .now
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: dailyReminderTime
        )

        Task { @MainActor in
            _ = await model.saveReminderSettings(
                enabled: dailyReminderEnabled,
                hour: dailyReminderEnabled ? components.hour : nil,
                minute: dailyReminderEnabled ? components.minute : nil,
                persistentIntervalMinutes: persistentIntervalMinutes
            )
            isSaving = false
        }
    }
}
