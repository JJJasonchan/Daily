import DailyCore
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel

    @State private var weekAnchor: LocalDay
    @State private var summaries: [HistoryDaySummary] = []
    @State private var loadFailed = false

    init(model: AppModel) {
        self.model = model
        _weekAnchor = State(initialValue: model.selectedHistoryDay)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                weekNavigation

                if loadFailed {
                    ContentUnavailableView(
                        "无法读取历史记录",
                        systemImage: "exclamationmark.triangle",
                        description: Text("请稍后重试。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    weekCells
                    selectedDayDetails
                }
            }
            .frame(maxWidth: 900)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("历史记录")
        .task(id: weekAnchor) {
            loadWeek()
        }
    }

    private var weekNavigation: some View {
        HStack {
            Button {
                shiftWeek(by: -7)
            } label: {
                Label("上一周", systemImage: "chevron.left")
            }

            Spacer()

            Text(weekRangeDescription)
                .font(.headline)

            Spacer()

            Button {
                shiftWeek(by: 7)
            } label: {
                Label("下一周", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderless)
    }

    private var weekCells: some View {
        HStack(spacing: 9) {
            ForEach(summaries) { summary in
                Button {
                    model.selectHistoryDay(summary.day)
                } label: {
                    VStack(spacing: 8) {
                        Text(weekdayText(summary.day))
                            .font(.caption.weight(.semibold))
                        Text(dayNumber(summary.day))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(countText(summary))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 94)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(intensity(summary)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(
                                    model.selectedHistoryDay == summary.day ? 0.72 : 0.12
                                ),
                                lineWidth: model.selectedHistoryDay == summary.day ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilitySummary(summary))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("七天完成情况")
    }

    @ViewBuilder
    private var selectedDayDetails: some View {
        if let summary = selectedSummary {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(fullDate(summary.day))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(countText(summary))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if summary.tasks.isEmpty {
                    Text("当天没有任务")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .glassModule(interactive: false, cornerRadius: 16)
                } else {
                    VStack(spacing: 8) {
                        ForEach(summary.tasks, id: \.0.id) { task, status in
                            HStack(spacing: 12) {
                                Image(systemName: statusSymbol(status))
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)
                                Text(task.titleSnapshot)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(statusText(status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .glassModule(interactive: false, cornerRadius: 14)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private var selectedSummary: HistoryDaySummary? {
        summaries.first { $0.day == model.selectedHistoryDay } ?? summaries.first
    }

    private var weekRangeDescription: String {
        guard let first = summaries.first, let last = summaries.last else { return "本周" }
        return "\(shortDate(first.day)) – \(shortDate(last.day))"
    }

    private func loadWeek() {
        do {
            summaries = try model.history(weekContaining: weekAnchor)
            loadFailed = false
            if !summaries.contains(where: { $0.day == model.selectedHistoryDay }),
               let first = summaries.first {
                model.selectHistoryDay(first.day)
            }
        } catch {
            summaries = []
            loadFailed = true
        }
    }

    private func shiftWeek(by days: Int) {
        let calendar = Calendar.autoupdatingCurrent
        weekAnchor = weekAnchor.adding(days: days, calendar: calendar)
    }

    private func date(_ day: LocalDay, format: Date.FormatStyle) -> String {
        day.date(in: Calendar.autoupdatingCurrent).formatted(format)
    }

    private func weekdayText(_ day: LocalDay) -> String {
        date(day, format: .dateTime.weekday(.abbreviated))
    }

    private func dayNumber(_ day: LocalDay) -> String {
        date(day, format: .dateTime.day())
    }

    private func shortDate(_ day: LocalDay) -> String {
        date(day, format: .dateTime.month(.abbreviated).day())
    }

    private func fullDate(_ day: LocalDay) -> String {
        date(day, format: .dateTime.year().month(.wide).day().weekday(.wide))
    }

    private func countText(_ summary: HistoryDaySummary) -> String {
        summary.totalCount == 0
            ? "无任务"
            : "\(summary.completedCount) / \(summary.totalCount)"
    }

    private func intensity(_ summary: HistoryDaySummary) -> Double {
        guard let fraction = summary.completionFraction else { return 0.04 }
        return 0.10 + fraction * 0.34
    }

    private func statusText(_ status: HistoryStatus) -> String {
        switch status {
        case .completed: "已完成"
        case .incomplete: "未完成"
        case .rolledOver: "已顺延"
        }
    }

    private func statusSymbol(_ status: HistoryStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .incomplete: "circle"
        case .rolledOver: "arrow.forward.circle"
        }
    }

    private func accessibilitySummary(_ summary: HistoryDaySummary) -> String {
        "\(fullDate(summary.day))，已完成 \(summary.completedCount) 项，共 \(summary.totalCount) 项"
    }
}
