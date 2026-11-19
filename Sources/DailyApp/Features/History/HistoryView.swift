import Charts
import DailyCore
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weekAnchor: LocalDay
    @State private var summaries: [HistoryDaySummary] = []
    @State private var loadFailed = false
    @State private var trend: [TrendPoint] = []
    @State private var currentStreak = 0
    @State private var longestStreak = 0
    @State private var trendRange = 7
    @State private var chartReveal: Double = 0
    @State private var hasEntered = false
    @State private var didReveal = false

    init(model: AppModel) {
        self.model = model
        _weekAnchor = State(initialValue: model.selectedHistoryDay)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loadFailed {
                    ContentUnavailableView(
                        "无法读取历史记录",
                        systemImage: "exclamationmark.triangle",
                        description: Text("请稍后重试。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    trendSection
                    weekNavigation
                    weekCells
                    selectedDayDetails
                }
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("历史记录")
        .task(id: HistoryLoadKey(week: weekAnchor, taskDataRevision: model.taskDataRevision)) {
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
            ForEach(summaries.indices, id: \.self) { index in
                let summary = summaries[index]
                Button {
                    model.selectHistoryDay(summary.day)
                } label: {
                    ZStack {
                        GeometryReader { proxy in
                            let fraction = summary.completionFraction ?? 0
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(ColorTokens.completionGreen.opacity(0.10))
                                Rectangle()
                                    .fill(ColorTokens.completionGreen.opacity(0.5))
                                    .frame(height: proxy.size.height * fraction)
                            }
                        }

                        VStack(spacing: 8) {
                            Text(weekdayText(summary.day))
                                .font(.caption.weight(.semibold))
                            Text(dayNumber(summary.day))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Text(countText(summary))
                                .font(.caption2)
                                .monospacedDigit()
                            Text(summary.percentageText)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                model.selectedHistoryDay == summary.day
                                    ? ColorTokens.completionGreen
                                    : Color.primary.opacity(0.12),
                                lineWidth: model.selectedHistoryDay == summary.day ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilitySummary(summary))
                .opacity(entranceOpacity)
                .offset(y: entranceOffset(index))
                .animation(cellEntranceAnimation(index), value: hasEntered)
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
                    Text(detailCountText(summary))
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
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(statusText(status))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let meta = taskMetaText(task, status) {
                                        Text(meta)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .monospacedDigit()
                                    }
                                }
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
            let today = model.currentDay
            trend = try model.completionTrend(ending: today, days: 30)
                .map { TrendPoint(day: $0.0, fraction: $0.1) }
            currentStreak = try model.currentStreak(ending: today)
            longestStreak = try model.longestStreak(ending: today, within: 365)
            loadFailed = false
            if !summaries.contains(where: { $0.day == model.selectedHistoryDay }),
               let first = summaries.first {
                model.selectHistoryDay(first.day)
            }
            triggerReveal()
        } catch {
            summaries = []
            trend = []
            currentStreak = 0
            longestStreak = 0
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

    private var calendar: Calendar { .autoupdatingCurrent }

    private var displayedTrend: [TrendPoint] {
        trendRange == 7 ? Array(trend.suffix(7)) : trend
    }

    private var chartDateRange: ClosedRange<Date> {
        let firstDay = displayedTrend.first?.day ?? model.currentDay
        let lastDay = displayedTrend.last?.day ?? firstDay
        let nextDay = lastDay.adding(days: 1, calendar: calendar)
        return firstDay.date(in: calendar)...nextDay.date(in: calendar)
    }

    private var chartAxisDates: [Date] {
        let points = displayedTrend
        let stride = trendRange == 7 ? 1 : 6
        return points.enumerated().compactMap { index, point in
            guard index.isMultiple(of: stride) || index == points.count - 1 else { return nil }
            return point.day.date(in: calendar)
        }
    }

    private var chartSpring: Animation {
        reduceMotion ? .linear(duration: 0) : .spring(duration: 0.7, bounce: 0.18)
    }

    private var entranceOpacity: Double {
        reduceMotion || hasEntered ? 1 : 0
    }

    private func entranceOffset(_ index: Int) -> CGFloat {
        guard !reduceMotion, !hasEntered else { return 0 }
        return 10
    }

    private func cellEntranceAnimation(_ index: Int) -> Animation? {
        if reduceMotion { return nil }
        return .spring(duration: 0.40, bounce: 0.16).delay(Double(index) * 0.045)
    }

    private func triggerReveal() {
        guard !didReveal else { return }
        didReveal = true
        Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(60))
            }
            chartReveal = 1
            hasEntered = true
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("完成趋势")
                    .font(.headline)
                Spacer()
                Picker("范围", selection: $trendRange) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("连续打卡 \(currentStreak) 天")
                    .font(.subheadline.weight(.semibold))
                if longestStreak > 0 {
                    Text("最长 \(longestStreak) 天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("每天至少有一项任务且全部完成才计入连续打卡。今天未达成时，显示截至昨天的连续天数。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(displayedTrend) { point in
                if let fraction = point.fraction {
                    let date = point.day.date(in: calendar)
                    if fraction == 0 {
                        PointMark(
                            x: .value("日期", date, unit: .day),
                            y: .value("完成率", 0.0)
                        )
                        .foregroundStyle(ColorTokens.completionGreen)
                        .accessibilityLabel(Text(fullDate(point.day)))
                        .accessibilityValue(Text("完成率 0%"))
                    } else {
                        BarMark(
                            x: .value("日期", date, unit: .day),
                            y: .value("完成率", fraction * chartReveal)
                        )
                        .foregroundStyle(ColorTokens.completionGreen)
                        .accessibilityLabel(Text(fullDate(point.day)))
                        .accessibilityValue(Text("完成率 \(Int((fraction * 100).rounded()))%"))
                    }
                }
            }
            .chartXScale(domain: chartDateRange)
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: chartAxisDates) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) {
                            Text("\(Int(fraction * 100))%")
                        }
                    }
                }
            }
            .frame(height: 180)
            .animation(chartSpring, value: chartReveal)
            Text("空白日期没有任务，基线上的圆点表示完成率为 0%。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .glassModule(interactive: false, cornerRadius: 18)
    }

    private func countText(_ summary: HistoryDaySummary) -> String {
        summary.totalCount == 0
            ? "无任务"
            : "\(summary.completedCount) / \(summary.totalCount)"
    }

    private func detailCountText(_ summary: HistoryDaySummary) -> String {
        summary.totalCount == 0
            ? "无任务"
            : "\(summary.completedCount) / \(summary.totalCount) · \(summary.percentageText)"
    }

    private func axisLabel(for date: Date) -> String {
        trendRange == 7
            ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func taskMetaText(_ task: DailyTask, _ status: HistoryStatus) -> String? {
        switch status {
        case .completed:
            guard let completedAt = task.completedAt else { return nil }
            return completedAt.formatted(date: .omitted, time: .shortened)
        case .rolledOver:
            return task.rolloverCount > 0 ? "累计顺延 \(task.rolloverCount) 次" : nil
        case .incomplete:
            return nil
        }
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
        case .completed: "✅"
        case .incomplete: "⬜"
        case .rolledOver: "➡️"
        }
    }

    private func accessibilitySummary(_ summary: HistoryDaySummary) -> String {
        let date = fullDate(summary.day)
        guard summary.totalCount > 0 else { return "\(date)，无任务" }
        return "\(date)，已完成 \(summary.completedCount) 项，共 \(summary.totalCount) 项"
    }
}

private struct TrendPoint: Identifiable {
    let day: LocalDay
    let fraction: Double?
    var id: String { day.rawValue }
}

private struct HistoryLoadKey: Equatable {
    let week: LocalDay
    let taskDataRevision: Int
}
