import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var hoveredDestination: AppModel.Destination?

    var body: some View {
        VStack(spacing: 2) {
            destinationRow("今日", systemImage: "checkmark.circle", value: .today)
            destinationRow("重复规则", systemImage: "repeat", value: .rules)
            destinationRow("历史记录", systemImage: "clock.arrow.circlepath", value: .history)

            Spacer(minLength: 12)

            destinationRow("设置", systemImage: "gearshape", value: .settings)

            SidebarTodayCard(model: model)
                .padding(.top, 10)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Daily")
        .frame(minWidth: 190, idealWidth: 220)
        .glassEffect(Glass.regular, in: Rectangle())
        .accessibilityLabel("主导航")
    }

    private func destinationRow(
        _ title: String,
        systemImage: String,
        value: AppModel.Destination
    ) -> some View {
        let isSelected = model.destination == value
        let isHovered = hoveredDestination == value

        return Button {
            model.destination = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? ColorTokens.accent.opacity(0.10)
                            : Color.primary.opacity(isHovered ? 0.05 : 0)
                    )
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered in
            hoveredDestination = isHovered ? value : nil
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarTodayCard: View {
    @Bindable var model: AppModel

    private var fraction: Double {
        guard !model.todayTasks.isEmpty else { return 0 }
        return Double(model.completedCount) / Double(model.todayTasks.count)
    }

    var body: some View {
        Group {
            if model.todayTasks.isEmpty {
                Text("今日暂无任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ProgressRing(
                        fraction: fraction,
                        size: 28,
                        lineWidth: 4,
                        showsLabel: false
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("今日进度")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(model.completedCount) / \(model.todayTasks.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .glassModule(interactive: false, cornerRadius: 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            model.todayTasks.isEmpty
                ? "今日暂无任务"
                : "今日进度 \(model.completedCount) / \(model.todayTasks.count)"
        )
    }
}
