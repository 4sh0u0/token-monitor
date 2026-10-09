import Charts
import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

enum TrendMetric: String, CaseIterable, Identifiable {
    case tokens
    case cost

    var id: String { rawValue }

    func format(_ value: Double) -> String {
        switch self {
        case .tokens: return TokenFormat.compactNumber(value)
        case .cost: return TokenFormat.usd(value)
        }
    }

    /// Axis ticks: short, so the axis stays narrow.
    func axisFormat(_ value: Double) -> String {
        switch self {
        case .tokens: return TokenFormat.compactNumber(value)
        case .cost: return TokenFormat.compactUSD(value)
        }
    }
}

struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let tokens: Int
    let costUsd: Double

    var id: Date { date }

    func value(_ metric: TrendMetric) -> Double {
        switch metric {
        case .tokens: return Double(tokens)
        case .cost: return costUsd
        }
    }

    /// The last `days` days ending today, today including the live period.
    static func series(from stats: HubStats, days: Int, calendar: Calendar = .current) -> [TrendPoint] {
        stats.dailyTrend(days: days, endingAt: Date(), calendar: calendar).compactMap { day in
            guard let date = day.startOfDay(in: calendar) else { return nil }
            return TrendPoint(date: date, tokens: day.tokens, costUsd: day.costUsd)
        }
    }
}

/// Daily tokens (or cost) for the last 14 or 30 days.
struct TrendChartCard: View {
    let stats: HubStats
    @AppStorage("overview.trendDays") private var days = 14
    @AppStorage("overview.trendMetric") private var metric: TrendMetric = .tokens
    @State private var selectedDate: Date? = nil

    var body: some View {
        let points = TrendPoint.series(from: stats, days: days == 30 ? 30 : 14)
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    CardTitle("Daily trend")
                    Spacer(minLength: 8)
                    Picker("Range", selection: $days) {
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.menu)
                }
                Picker("Metric", selection: $metric) {
                    Text("Tokens").tag(TrendMetric.tokens)
                    Text("Cost").tag(TrendMetric.cost)
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    Text("No activity yet.")
                        .font(.subheadline)
                        .foregroundStyle(TMTheme.muted)
                } else {
                    TrendSummary(points: points, metric: metric, selectedDate: selectedDate)
                    TrendChart(points: points, metric: metric, selectedDate: $selectedDate)
                        .frame(height: 180)
                }
                if stats.history.isEmpty {
                    Text("Earlier days appear once your devices report their history to the Hub.")
                        .font(.caption)
                        .foregroundStyle(TMTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The selected day's value, or the range total.
private struct TrendSummary: View {
    let points: [TrendPoint]
    let metric: TrendMetric
    let selectedDate: Date?

    private var selectedPoint: TrendPoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        let selected = selectedPoint
        let value = selected.map { $0.value(metric) } ?? points.reduce(0) { $0 + $1.value(metric) }
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let selected {
                    Text(selected.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                } else {
                    Text("Total")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(TMTheme.muted)
            Text(verbatim: metric.format(value))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TMTheme.number)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TrendChart: View {
    let points: [TrendPoint]
    let metric: TrendMetric
    @Binding var selectedDate: Date?

    private var labelStride: Int { points.count > 14 ? 7 : 3 }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Value", point.value(metric))
            )
            .foregroundStyle(isSelected(point) ? TMTheme.accent : TMTheme.chartBar)
            .cornerRadius(3)
            .accessibilityLabel(Text(point.date, format: .dateTime.month(.wide).day()))
            .accessibilityValue(Text(verbatim: metric.format(point.value(metric))))
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: labelStride)) { _ in
                AxisGridLine()
                    .foregroundStyle(TMTheme.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(TMTheme.divider)
                AxisValueLabel {
                    Text(verbatim: metric.axisFormat(value.as(Double.self) ?? 0))
                }
            }
        }
    }

    private func isSelected(_ point: TrendPoint) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.current.isDate(point.date, inSameDayAs: selectedDate)
    }
}
