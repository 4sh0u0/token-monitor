import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

/// Activity: the desktop's Activity mosaic (Sunday-first week columns,
/// intensity against the busiest day), from the compact file the app writes
/// after loading History. Medium shows the most recent ~20 weeks, large the
/// rolling 12 months.
struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.activity,
            intent: ActivityWidgetIntent.self,
            provider: ActivityTimelineProvider()
        ) { entry in
            ActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Activity")
        .description("Daily usage over the last 12 months as a heatmap.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    var body: some View {
        WidgetChrome(url: url, context: entry.context) {
            content
        }
    }

    private var url: URL {
        if case .notConfigured = entry.state { return WidgetLink.settings }
        return WidgetLink.trends
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .notConfigured:
            WidgetMessageView(message: .notConfigured)
        case .missing:
            WidgetMessageView(message: .noActivity)
        case .ready(let snapshot):
            if family == .systemLarge {
                ActivityLargeView(entry: entry, snapshot: snapshot)
            } else {
                ActivityMediumView(entry: entry, snapshot: snapshot)
            }
        }
    }
}

// MARK: - Building blocks

/// "ACTIVITY · device ⏱" on the left, `trailing` on the right.
struct ActivityHeader<Trailing: View>: View {
    let entry: ActivityEntry
    let trailing: Trailing

    init(entry: ActivityEntry, @ViewBuilder trailing: () -> Trailing) {
        self.entry = entry
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 4) {
            SectionLabel(text: WidgetText.activity)
            if let scopeName = entry.scopeName { ScopeLabel(name: scopeName) }
            if entry.isStale { StaleBadge() }
            Spacer(minLength: 4)
            trailing
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: ActivityGridLayout.headerHeight)
    }
}

/// Sizing of the mosaic inside a widget.
enum ActivityGridLayout {
    static let headerHeight: CGFloat = 16
    static let monthLabelSize: CGFloat = 9

    /// The month-label row `ActivityHeatmapView` draws under the grid.
    static var labelRowHeight: CGFloat { 3 + (monthLabelSize * 1.3).rounded(.up) }

    /// The largest cell that fits `weeks` columns, and the grid with its
    /// labels, in `size`; clamped to `range`.
    static func cellSize(fitting size: CGSize, weeks: Int, spacing: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        let byWidth = ActivityHeatmapView.fittedCellSize(width: size.width, weeks: max(1, weeks), spacing: spacing, range: range)
        let byHeight = (size.height - labelRowHeight - 6 * spacing) / 7
        guard byHeight.isFinite else { return range.lowerBound }
        return max(range.lowerBound, min(byWidth, byHeight))
    }

    static func cornerRadius(_ cellSize: CGFloat) -> CGFloat {
        min(2, cellSize / 4)
    }
}

extension HeatmapGrid {
    /// The oldest `count` week columns (the large widget's first half);
    /// levels and labels unchanged.
    func leading(weeks count: Int) -> HeatmapGrid {
        guard count < weeks else { return self }
        guard count > 0 else {
            return HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: startDate, endDate: startDate, metric: metric)
        }
        let kept = cells.filter { $0.column < count }
        let labels = monthLabels.filter { $0.column < count }
        let end = kept.last.map { min($0.date, endDate) } ?? startDate
        return HeatmapGrid(cells: kept, weeks: count, monthLabels: labels, startDate: startDate, endDate: end, metric: metric)
    }
}

// MARK: - Families

/// systemMedium: the most recent weeks (about 20, as many as fit), with the
/// active days among them.
struct ActivityMediumView: View {
    let entry: ActivityEntry
    let snapshot: ActivitySnapshot

    private static let targetWeeks = 20
    private static let maxWeeks = 26
    private static let spacing: CGFloat = 6
    private static let cellSpacing: CGFloat = 2.5

    var body: some View {
        let grid = snapshot.heatmap(metric: entry.metric, today: entry.date)
        GeometryReader { proxy in
            let area = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - ActivityGridLayout.headerHeight - Self.spacing))
            let cell = ActivityGridLayout.cellSize(fitting: area, weeks: min(grid.weeks, Self.targetWeeks), spacing: Self.cellSpacing, range: 5...14)
            let fitting = ActivityHeatmapView.weeksFitting(width: area.width, cellSize: cell, spacing: Self.cellSpacing)
            let weeks = max(1, min(grid.weeks, Self.maxWeeks, fitting))
            let visible = grid.trailing(weeks: weeks)
            VStack(alignment: .leading, spacing: Self.spacing) {
                ActivityHeader(entry: entry) {
                    Text(verbatim: WidgetText.activeDays(visible.activeDayCount, window: .all))
                }
                ActivityHeatmapView(
                    grid: grid,
                    cellSize: cell,
                    spacing: Self.cellSpacing,
                    cornerRadius: ActivityGridLayout.cornerRadius(cell),
                    visibleWeeks: weeks,
                    monthLabelSize: ActivityGridLayout.monthLabelSize,
                    monthLabel: WidgetText.monthLabel
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Activity heatmap"))
            }
        }
    }
}

/// systemLarge: the rolling 12 months in two rows of week columns, the
/// Less/More legend, and the active days and peak day.
struct ActivityLargeView: View {
    @Environment(\.tmFormatter) private var format
    let entry: ActivityEntry
    let snapshot: ActivitySnapshot

    private static let spacing: CGFloat = 8
    private static let cellSpacing: CGFloat = 2.25
    /// Header, legend and summary lines with the spacing between the rows.
    private static let chromeHeight: CGFloat = ActivityGridLayout.headerHeight + 14 + 14 + 5 * spacing

    var body: some View {
        let grid = snapshot.heatmap(metric: entry.metric, today: entry.date)
        let recentWeeks = (grid.weeks + 1) / 2
        let olderWeeks = grid.weeks - recentWeeks
        GeometryReader { proxy in
            let rowHeight = max(0, (proxy.size.height - Self.chromeHeight) / 2)
            let cell = ActivityGridLayout.cellSize(
                fitting: CGSize(width: proxy.size.width, height: rowHeight),
                weeks: recentWeeks,
                spacing: Self.cellSpacing,
                range: 4...12
            )
            VStack(alignment: .leading, spacing: Self.spacing) {
                ActivityHeader(entry: entry) {
                    Text(verbatim: WidgetText.metric(entry.metric))
                }
                VStack(alignment: .leading, spacing: Self.spacing) {
                    if olderWeeks > 0 {
                        heatmap(grid.leading(weeks: olderWeeks), cell: cell, visibleWeeks: nil)
                    }
                    heatmap(grid, cell: cell, visibleWeeks: recentWeeks)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Activity heatmap"))
                .accessibilityValue(Text(verbatim: summary(grid)))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    HeatmapLegend(less: WidgetText.less, more: WidgetText.more, cellSize: 8, spacing: 2, cornerRadius: 1.5)
                    Spacer(minLength: 4)
                    if entry.isStale {
                        UpdatedFootnote(fetchedAt: snapshot.generatedAt, now: entry.date, isStale: true)
                    }
                }
                Text(verbatim: summary(grid))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func heatmap(_ grid: HeatmapGrid, cell: CGFloat, visibleWeeks: Int?) -> some View {
        ActivityHeatmapView(
            grid: grid,
            cellSize: cell,
            spacing: Self.cellSpacing,
            cornerRadius: ActivityGridLayout.cornerRadius(cell),
            visibleWeeks: visibleWeeks,
            monthLabelSize: ActivityGridLayout.monthLabelSize,
            monthLabel: WidgetText.monthLabel
        )
    }

    /// "214 active days · Peak 48.2M": the active-days chip as the app's
    /// Activity module counts it (`homeActiveDaysWindow`), and the busiest day.
    private func summary(_ grid: HeatmapGrid) -> String {
        let window = entry.context.preferences.homeActiveDaysWindow
        var parts = [WidgetText.activeDays(snapshot.activeDays(window: window, grid: grid), window: window)]
        let peak = snapshot.peakDayTokens
        if peak > 0 { parts.append(WidgetText.peak(peak, format)) }
        return parts.joined(separator: " · ")
    }
}

#Preview(as: .systemMedium) {
    ActivityWidget()
} timeline: {
    ActivityEntry.preview()
    ActivityEntry.preview(metric: .tokens, scoped: true)
    ActivityEntry.preview(generatedDaysAgo: 2)
    ActivityEntry(date: Date(), state: .missing)
}

#Preview(as: .systemLarge) {
    ActivityWidget()
} timeline: {
    ActivityEntry.preview()
    ActivityEntry.preview(metric: .tokens, scoped: true, generatedDaysAgo: 2)
    ActivityEntry(date: Date(), state: .notConfigured)
}
