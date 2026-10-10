import SwiftUI
import TokenMonitorKit
import TokenMonitorUI

/// The Trends chart card (the desktop dashboard's Trends tab, plus iOS's Line
/// mode and cost metric): chart style, range, metric and stack pickers, a
/// readout of the selected day (or candle) or of the whole range, the chart,
/// and the stack legend.
///
/// - Bars stack by tool (`perClient`) or model (`perModel`), biggest key at
///   the bottom; on the stats preview, which has no buckets, they are plain
///   totals and the stack picker is hidden.
/// - Line is the Home "Trend" smooth area line.
/// - K-line buckets days into candles sized to the plot width
///   (`TrendSeriesBuilder.klineBucketDays`), green up, red down.
///
/// Every range is calendar days ending today, zero-filled (plan
/// D-RANGEFILL), with live today patched in (D-TODAYPATCH).
struct TrendChartSection: View {
    @Environment(\.tmPresentation) private var presentation
    @Environment(\.tmFormatter) private var formatter
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The range's days, oldest first (`HistoryStore.trendDays(_:)`).
    let days: [HubHistoryDay]
    /// The days carry tool and model buckets (not the stats preview).
    let canStack: Bool
    /// The ranges on offer.
    let ranges: [TrendRange]
    @Binding var mode: TrendChartMode
    @Binding var range: TrendRange
    @Binding var stack: TrendStack
    @Binding var metric: TrendMetricKind

    @State private var selection: String?
    @State private var chartWidth: CGFloat = 0
    @State private var showsAllKeys = false

    /// Legend chips shown before "Show all".
    private static let legendLimit = 10
    /// Day segments listed for a selected bar.
    private static let segmentLimit = 6

    var body: some View {
        let bars = mode == .bars ? barsModel : .empty
        let stacked = mode == .bars && canStack && !bars.keys.isEmpty
        let candles = mode == .kline ? candleModel : []
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                controls(stackable: canStack)
                readout(bars: bars, stacked: stacked, candles: candles)
                chart(bars: bars, stacked: stacked, candles: candles)
                    .frame(height: sizeClass == .regular ? 280 : 220)
                    .trendsMeasuringWidth($chartWidth)
                if stacked {
                    legend(bars)
                }
            }
        }
        .onChange(of: mode) { _, _ in selection = nil }
        .onChange(of: range) { _, _ in selection = nil }
        .onChange(of: stack) { _, _ in
            selection = nil
            showsAllKeys = false
        }
        .onChange(of: metric) { _, _ in selection = nil }
    }

    // MARK: Data

    private var barsModel: TrendBarsModel {
        if canStack {
            let model = TrendSeriesBuilder.bars(days: days, stack: stack, metric: metric)
            if !model.keys.isEmpty { return model }
        }
        return Self.totalBars(days, metric: metric)
    }

    /// One unstacked bar per day (the preview, or rows without buckets).
    private static func totalBars(_ days: [HubHistoryDay], metric: TrendMetricKind) -> TrendBarsModel {
        var maxTotal = 1.0
        let bars = days.map { day -> TrendBar in
            let value = TrendSeriesBuilder.value(of: day, metric: metric)
            maxTotal = max(maxTotal, value)
            return TrendBar(date: day.date, total: value, segments: [TrendBarSegment(key: totalKey, value: value)])
        }
        return TrendBarsModel(keys: [totalKey], bars: bars, maxTotal: maxTotal)
    }

    private static let totalKey = "total"

    private var candleModel: [TrendCandle] {
        // The value axis takes about 48 pt of the chart's width.
        TrendSeriesBuilder.candles(days: days, metric: metric, plotWidth: Double(max(0, chartWidth - 48)))
    }

    private func value(_ number: Double) -> String {
        TrendsFormat.value(number, metric: metric, formatter: formatter)
    }

    private func color(_ key: String, stacked: Bool) -> Color {
        guard stacked else { return TMTheme.chartBar }
        switch stack {
        case .client: return VendorColor.color(for: key, palette: presentation.palette)
        case .model: return VendorColor.model(key, palette: presentation.palette)
        }
    }

    private func name(_ key: String) -> String {
        switch stack {
        case .client: return VendorCatalog.clientLabel(key)
        case .model: return key
        }
    }

    private var chartLabels: TrendChartLabels {
        TrendChartLabels(
            date: String(localized: "Date"),
            value: metric == .tokens ? String(localized: "Tokens") : String(localized: "Cost")
        )
    }

    private var maxDateLabels: Int { sizeClass == .regular ? 8 : 5 }

    // MARK: Controls

    private func controls(stackable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Chart style", selection: $mode) {
                Text("Bars").tag(TrendChartMode.bars)
                Text("Line").tag(TrendChartMode.line)
                Text("K-line").tag(TrendChartMode.kline)
            }
            .pickerStyle(.segmented)
            Picker("Range", selection: $range) {
                ForEach(ranges) { option in
                    Self.rangeLabel(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metricPicker
                    if mode == .bars && stackable { stackPicker }
                }
                VStack(alignment: .leading, spacing: 10) {
                    metricPicker
                    if mode == .bars && stackable { stackPicker }
                }
            }
        }
    }

    /// The dashboard's range buttons (`dashboard.range.*`).
    private static func rangeLabel(_ range: TrendRange) -> Text {
        switch range {
        case .days7: return Text("7 days")
        case .days30: return Text("30 days")
        case .days90: return Text("90 days")
        case .days365: return Text("1 year")
        case .all: return Text("All")
        }
    }

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            Text("Tokens").tag(TrendMetricKind.tokens)
            Text("Cost").tag(TrendMetricKind.cost)
        }
        .pickerStyle(.segmented)
    }

    private var stackPicker: some View {
        Picker("Stack by", selection: $stack) {
            Text("By tool").tag(TrendStack.client)
            Text("By model").tag(TrendStack.model)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Readout

    /// The selected day (or candle), else the whole range: the metric as the
    /// headline and the other metric beside it; a selected stacked bar also
    /// lists its biggest segments, a selected candle its open, high, low and
    /// close (the dashboard's tooltips).
    @ViewBuilder
    private func readout(bars: TrendBarsModel, stacked: Bool, candles: [TrendCandle]) -> some View {
        if mode == .kline, let key = selection, let candle = candles.first(where: { $0.key == key }) {
            candleReadout(candle)
        } else if mode != .kline, let key = selection, let day = days.first(where: { $0.date == key }) {
            VStack(alignment: .leading, spacing: 8) {
                totals(
                    caption: TrendsFormat.longDate(day.date),
                    tokens: day.tokens,
                    costUsd: day.costUsd,
                    unpricedTokens: day.unpricedTokens
                )
                if stacked, let bar = bars.bars.first(where: { $0.date == key }) {
                    segments(bar, stacked: stacked)
                }
            }
        } else {
            totals(
                caption: TrendsFormat.rangeTitle(range),
                tokens: days.reduce(0) { $0 + $1.tokens },
                costUsd: days.reduce(0) { $0 + $1.costUsd },
                unpricedTokens: days.reduce(0) { $0 + ($1.unpricedTokens ?? 0) }
            )
        }
    }

    private func totals(caption: String, tokens: Int, costUsd: Double, unpricedTokens: Int?) -> some View {
        let cost = CostLabelText.string(usd: costUsd, unpricedTokens: unpricedTokens, compact: true, compactAmount: true, formatter: formatter)
        let tokenText = formatter.compactTokens(tokens)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: metric == .tokens ? tokenText : cost)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TMTheme.number)
                    .contentTransition(.numericText())
                Group {
                    if metric == .tokens {
                        Text("Cost") + Text(verbatim: " " + cost)
                    } else {
                        Text("Tokens") + Text(verbatim: " " + tokenText)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(TMTheme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func segments(_ bar: TrendBar, stacked: Bool) -> some View {
        let rows = bar.segments.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let shown = rows.prefix(Self.segmentLimit)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(shown)) { segment in
                HStack(spacing: 6) {
                    MarkDot(color: color(segment.key, stacked: stacked))
                    Text(verbatim: name(segment.key))
                        .foregroundStyle(TMTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(verbatim: value(segment.value))
                        .monospacedDigit()
                        .foregroundStyle(TMTheme.muted)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
            if rows.count > shown.count {
                Text(verbatim: String(localized: "+\(rows.count - shown.count) more"))
                    .font(.caption2)
                    .foregroundStyle(TMTheme.muted)
            }
        }
    }

    private func candleReadout(_ candle: TrendCandle) -> some View {
        let caption = candle.endKey != candle.key
            ? TrendsFormat.shortDate(candle.key) + " – " + TrendsFormat.shortDate(candle.endKey)
            : TrendsFormat.longDate(candle.key)
        // The dashboard's candle tooltip rows (O/H/L/C, not localized there).
        let rows: [(String, Double)] = [("O", candle.open), ("H", candle.high), ("L", candle.low), ("C", candle.close)]
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(TMTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: row.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TMTheme.muted)
                        Text(verbatim: value(row.1))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(row.0 == "C" ? (candle.up ? TMTheme.candleUp : TMTheme.candleDown) : TMTheme.number)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: caption))
        .accessibilityValue(Text(verbatim: spokenCandle(candle)))
    }

    private func spokenCandle(_ candle: TrendCandle) -> String {
        let open = value(candle.open)
        let high = value(candle.high)
        let low = value(candle.low)
        let close = value(candle.close)
        return String(localized: "Open \(open), high \(high), low \(low), close \(close)")
    }

    // MARK: Chart

    @ViewBuilder
    private func chart(bars: TrendBarsModel, stacked: Bool, candles: [TrendCandle]) -> some View {
        switch mode {
        case .bars:
            TrendBarsChart(
                model: bars,
                selection: $selection,
                color: { color($0, stacked: stacked) },
                seriesName: { stacked ? name($0) : chartLabels.value },
                axisValue: value,
                dateLabel: TrendsFormat.axisDate,
                maxDateLabels: maxDateLabels,
                labels: chartLabels
            )
        case .line:
            TrendAreaLineChart(
                points: TrendSeriesBuilder.line(days: days, metric: metric),
                selection: $selection,
                axisValue: value,
                dateLabel: TrendsFormat.axisDate,
                maxDateLabels: maxDateLabels,
                labels: chartLabels
            )
        case .kline:
            TrendCandleChart(
                candles: candles,
                selection: $selection,
                axisValue: value,
                dateLabel: TrendsFormat.axisDate,
                maxDateLabels: maxDateLabels,
                labels: chartLabels,
                candleValue: spokenCandle
            )
        }
    }

    // MARK: Legend

    /// The stack keys over the range, biggest first (the dashboard's legend
    /// without its values; the top lists below carry those).
    private func legend(_ bars: TrendBarsModel) -> some View {
        var totals: [String: Double] = [:]
        for bar in bars.bars {
            for segment in bar.segments { totals[segment.key, default: 0] += segment.value }
        }
        let keys = bars.keys.filter { (totals[$0] ?? 0) > 0 }
        let shown = showsAllKeys ? keys : Array(keys.prefix(Self.legendLimit))
        return VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 10, lineSpacing: 6) {
                ForEach(shown, id: \.self) { key in
                    HStack(spacing: 5) {
                        MarkDot(color: color(key, stacked: true))
                        Text(verbatim: name(key))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .foregroundStyle(TMTheme.muted)
                    .accessibilityElement(children: .combine)
                }
            }
            if keys.count > Self.legendLimit {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsAllKeys.toggle() }
                } label: {
                    if showsAllKeys {
                        Text("Show less")
                    } else {
                        Text("Show all")
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(TMTheme.accent)
            }
        }
    }
}
