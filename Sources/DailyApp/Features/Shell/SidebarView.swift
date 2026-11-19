import SwiftUI

struct SidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Bindable var model: AppModel
    let wallpaperPalette: WallpaperPalette
    @State private var hoveredDestination: AppModel.Destination?
    @FocusState private var focusedDestination: AppModel.Destination?

    private let destinations: [AppModel.Destination] = [.today, .rules, .history, .memo, .settings]

    var body: some View {
        VStack(spacing: 2) {
            destinationRow("今日", systemImage: "checkmark.circle", value: .today, shortcut: "⌘1")
            destinationRow("重复规则", systemImage: "repeat", value: .rules, shortcut: "⌘2")
            destinationRow("历史记录", systemImage: "clock.arrow.circlepath", value: .history, shortcut: "⌘3")
            destinationRow("备忘录", systemImage: "note.text", value: .memo, shortcut: "⌘4")

            Spacer(minLength: 12)

            destinationRow("设置", systemImage: "gearshape", value: .settings, shortcut: "⌘5")

            SidebarTodayCard(model: model)
                .padding(.top, 10)
        }
        .fluidTooltipScope(leadingInset: 29, height: 28)
        .padding(.horizontal, 8)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Daily")
        .frame(minWidth: 190, idealWidth: 220)
        .background {
            sidebarBackground
                .ignoresSafeArea()
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.28),
            value: wallpaperPalette
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主导航")
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private func destinationRow(
        _ title: String,
        systemImage: String,
        value: AppModel.Destination,
        shortcut: String
    ) -> some View {
        let isSelected = model.destination == value
        let isHovered = hoveredDestination == value

        return Button {
            model.destination = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? ColorTokens.accent : Color.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedDestination, equals: value)
        .onHover { hovering in
            if hovering {
                hoveredDestination = value
            } else if hoveredDestination == value {
                hoveredDestination = nil
            }
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end]) { press in
            switch press.key {
            case .home:
                focusedDestination = destinations.first
            case .end:
                focusedDestination = destinations.last
            default:
                guard let index = destinations.firstIndex(of: value) else { return .ignored }
                let step = press.key == .upArrow || press.key == .leftArrow ? -1 : 1
                focusedDestination = destinations[(index + step + destinations.count) % destinations.count]
            }
            return .handled
        }
        .fluidTooltip(title, shortcut: shortcut, isHovered: isHovered, isFocused: focusedDestination == value)
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
                        size: 24,
                        lineWidth: 4,
                        tint: ColorTokens.accent,
                        showsLabel: false,
                        completed: model.completedCount,
                        total: model.todayTasks.count
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
        .padding(.vertical, 6)
        .glassModule(
            interactive: false,
            cornerRadius: 12
        )
        .shadow(
            color: .black.opacity(0.10),
            radius: 8,
            y: 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            model.todayTasks.isEmpty
                ? "今日暂无任务"
                : "今日进度 \(model.completedCount) / \(model.todayTasks.count)"
        )
    }
}
