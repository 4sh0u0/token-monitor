import SwiftUI
import TokenMonitorKit
import TokenMonitorUI
import WidgetKit

enum UsageTrend {
    /// The sparkline series of a period: the last two weeks for today, this
    /// month's days for the month, every cached day for all time. Empty for a
    /// scoped device, whose History is not part of the snapshot.
    static func values(_ snapshot: TokenSnapshot, period: UsagePeriodKind) -> [Double] {
        let days = snapshot.trend
        switch period {
        case .today:
            return days.suffix(14).map { Double($0.tokens) }
        case .month:
            guard let last = days.last else { return [] }
            let monthKey = String(last.date.prefix(7))
            let thisMonth = days.filter { $0.date.hasPrefix(monthKey) }
            // Early in the month there is no line to draw yet.
            let series = thisMonth.count > 1 ? thisMonth : Array(days.suffix(14))
            return series.map { Double($0.tokens) }
        case .allTime:
            return days.map { Double($0.tokens) }
        }
    }

    /// Today against the busiest day of the last two weeks (the circular gauge).
    static func todayFraction(_ snapshot: TokenSnapshot) -> Double? {
        let peak = snapshot.trend.suffix(14).map { $0.tokens }.max() ?? 0
        guard peak > 0 else { return nil }
        return min(1, Double(snapshot.today.totalTokens) / Double(peak))
    }

    /// "$31.84 · 62 tok/s" (the rate only when the period was timed).
    static func costLine(_ summary: PeriodSummary, _ format: DisplayFormatter) -> String {
        var parts = [WidgetText.cost(summary, format)]
        if let rate = rateText(summary, format) { parts.append(rate) }
        return parts.joined(separator: " · ")
    }

    static func rateText(_ summary: PeriodSummary, _ format: DisplayFormatter) -> String? {
        guard let rate = summary.outputTokensPerSecond, rate > 0 else { return nil }
        return WidgetText.rate(rate, format)
    }

    /// Tools or models of the period, with an "Other" row for the rest.
    /// Tools are already in the user's order, minus hidden ones
    /// (`SnapshotBuilder`).
    static func shares(_ summary: PeriodSummary, breakdown: BreakdownOption) -> [UsageShare] {
        switch breakdown {
        case .tools: return summary.tools(otherLabel: WidgetText.other)
        case .models: return summary.models(otherLabel: WidgetText.other)
        }
    }
}

// MARK: - Building blocks

/// Header, coloured share bar and the top rows of a Tools/Models breakdown.
struct BreakdownList: View {
    @Environment(\.tmPresentation) private var presentation
    let title: String
    /// Nil when the period's figures are unknown (`TokenEntry.periodSummary`).
    let shares: [UsageShare]?
    let total: Int
    let maxRows: Int
    let showsRefresh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                SectionLabel(text: title)
                Spacer(minLength: 0)
                if showsRefresh { RefreshButton() }
            }
            if let shares, !shares.isEmpty, total > 0 {
                UsageBar(segments: segments(shares), total: Double(total), height: 6)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(shares.prefix(maxRows))) { share in
                        ShareRow(share: share, total: total)
                    }
                }
            } else if shares == nil {
                Text(verbatim: WidgetText.noValue)
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
            } else {
                Text("No usage yet")
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
            }
        }
    }

    private func segments(_ shares: [UsageShare]) -> [UsageBar.Segment] {
        let palette = presentation.palette
        return shares.map { UsageBar.Segment(id: $0.id, value: Double($0.tokens), color: ShareStyle.color($0, palette: palette)) }
    }
}

struct ShareRow: View {
    @Environment(\.tmFormatter) private var format
    let share: UsageShare
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ShareMark(share: share, size: 12)
            Text(verbatim: share.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: format.compactTokens(share.tokens))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
            Text(verbatim: WidgetText.share(share.fraction(of: total), format))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted.opacity(0.75))
                .lineLimit(1)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Total, cost and throughput of a period, with the trend and the update
/// time below. The left half of the medium widget.
struct UsageSummaryColumn: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let summary = entry.periodSummary
        VStack(alignment: .leading, spacing: 0) {
            PeriodHeader(period: entry.period, isStale: entry.isStale, scopeName: entry.scopeName)
            TotalTokensText(tokens: summary?.totalTokens, size: 30)
                .padding(.top, 3)
            Text(verbatim: WidgetText.cost(summary, format))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
            if let summary, let rate = UsageTrend.rateText(summary, format) {
                Text(verbatim: rate)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.muted)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            Spacer(minLength: 4)
            TrendLine(values: UsageTrend.values(snapshot, period: entry.period))
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: 22)
            UpdatedFootnote(fetchedAt: snapshot.fetchedAt, now: entry.date, isStale: entry.isStale)
                .padding(.top, 4)
        }
    }
}

// MARK: - Families

/// systemSmall: the period total, cost, trend and update time.
struct UsageSmallView: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let summary = entry.periodSummary
        VStack(alignment: .leading, spacing: 0) {
            PeriodHeader(period: entry.period, isStale: entry.isStale, scopeName: entry.scopeName)
            TotalTokensText(tokens: summary?.totalTokens, size: 34)
                .padding(.top, 2)
            Text(verbatim: WidgetText.cost(summary, format))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            TrendLine(values: UsageTrend.values(snapshot, period: entry.period))
                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 30)
            UpdatedFootnote(fetchedAt: snapshot.fetchedAt, now: entry.date, isStale: entry.isStale)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// systemMedium: the summary on the left, the breakdown on the right.
struct UsageMediumView: View {
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let summary = entry.periodSummary
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 14) {
                UsageSummaryColumn(entry: entry, snapshot: snapshot)
                    .frame(width: proxy.size.width * 0.42, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                BreakdownList(
                    title: WidgetText.breakdownTitle(entry.breakdown),
                    shares: summary.map { UsageTrend.shares($0, breakdown: entry.breakdown) },
                    total: summary?.totalTokens ?? 0,
                    maxRows: 4,
                    showsRefresh: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// systemLarge: a dashboard — total and trend, the breakdown, and the AI
/// tool limits in the Limits widget's automatic order.
struct UsageLargeView: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        GeometryReader { proxy in
            content(height: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func content(height: CGFloat) -> some View {
        let summary = entry.periodSummary
        let candidates = LimitSelection.providers(in: snapshot, pinnedID: nil, preferences: entry.preferences, limit: 3)
        // Large widgets range from ~290 pt (4.7") to ~350 pt (6.7") of
        // content height; trade rows for fit instead of clipping.
        let limitRows = candidates.isEmpty ? 0 : (height >= 340 ? 3 : 2)
        let shareRows = limitRows == 0 ? (height >= 300 ? 7 : 6) : (height >= 300 ? 4 : 3)
        let providers = Array(candidates.prefix(limitRows))
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                PeriodHeader(period: entry.period, isStale: entry.isStale, scopeName: entry.scopeName)
                Spacer(minLength: 4)
                UpdatedFootnote(fetchedAt: snapshot.fetchedAt, now: entry.date, isStale: entry.isStale)
                RefreshButton()
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    TotalTokensText(tokens: summary?.totalTokens, size: 36)
                    Text(verbatim: summary.map { UsageTrend.costLine($0, format) } ?? WidgetText.noValue)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                TrendLine(values: UsageTrend.values(snapshot, period: entry.period))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            Hairline()
            BreakdownList(
                title: WidgetText.breakdownTitle(entry.breakdown),
                shares: summary.map { UsageTrend.shares($0, breakdown: entry.breakdown) },
                total: summary?.totalTokens ?? 0,
                maxRows: shareRows,
                showsRefresh: false
            )
            if !providers.isEmpty {
                Hairline()
                Link(destination: WidgetLink.limits) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: WidgetText.limits)
                        ForEach(providers) { provider in
                            LimitMeterRow(provider: provider, now: entry.date)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// accessoryCircular: the period total; today is drawn against the busiest
/// recent day.
struct UsageCircularView: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let summary = entry.periodSummary
        AccessoryTokensGauge(
            valueText: summary.map { format.compactTokens($0.totalTokens) } ?? WidgetText.noValue,
            label: WidgetText.shortPeriod(entry.period),
            fraction: entry.period == .today && summary != nil ? UsageTrend.todayFraction(snapshot) : nil
        )
    }
}

/// accessoryRectangular: period (and scoped device), tokens with the trend,
/// and the cost (or, when the data is old, when it was last updated).
struct UsageRectangularView: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        let summary = entry.periodSummary
        AccessorySummaryView(
            title: title,
            value: summary.map { WidgetText.tokenCount($0.totalTokens, format) } ?? WidgetText.noValue,
            detail: entry.isStale || summary == nil
                ? WidgetText.updated(snapshot.fetchedAt, now: entry.date)
                : WidgetText.cost(summary, format),
            trend: Array(UsageTrend.values(snapshot, period: entry.period).suffix(14))
        )
    }

    private var title: String {
        [WidgetText.period(entry.period), entry.scopeName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// accessoryInline: "18.4M tokens · $31.84"; once the period has rolled
/// over since the fetch, when the numbers were last read instead (the line
/// has no room for a stale mark).
struct UsageInlineView: View {
    @Environment(\.tmFormatter) private var format
    let entry: TokenEntry
    let snapshot: TokenSnapshot

    var body: some View {
        if let summary = entry.periodSummary {
            let tokens = format.compactTokens(summary.totalTokens)
            let cost = WidgetText.cost(summary, format)
            Text("\(tokens) tokens · \(cost)")
        } else {
            Text(verbatim: WidgetText.updated(snapshot.fetchedAt, now: entry.date))
        }
    }
}
