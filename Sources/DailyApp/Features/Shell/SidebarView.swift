import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.destination) {
            Section {
                destinationRow("今日", systemImage: "checkmark.circle", value: .today)
                destinationRow("重复规则", systemImage: "repeat", value: .rules)
                destinationRow("历史记录", systemImage: "clock.arrow.circlepath", value: .history)
            }

            Section {
                destinationRow("设置", systemImage: "gearshape", value: .settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Daily")
        .frame(minWidth: 190, idealWidth: 220)
        .accessibilityLabel("主导航")
    }

    private func destinationRow(
        _ title: String,
        systemImage: String,
        value: AppModel.Destination
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
            .padding(.vertical, 3)
            .tag(value)
            .accessibilityLabel(title)
    }
}
