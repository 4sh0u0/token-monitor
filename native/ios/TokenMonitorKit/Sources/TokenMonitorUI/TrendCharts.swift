#if canImport(SwiftUI) && canImport(Charts)
import Charts
import SwiftUI
import TokenMonitorKit

// The Trends charts (desktop dashboard `barsChartSvg` / `candleChartSvg` and
// the Home `areaLineChart(curve: true)`), on Swift Charts. Every chart plots
// its days as categories (`yyyy-MM-dd` strings), evenly spaced like the
// desktop's slots, so a selection is the day (or candle) key. All text is
// supplied by the caller: `axisValue` formats value ticks, `dateLabel` day
// keys, and `TrendChartLabels` names the axes for VoiceOver.

/// What VoiceOver calls a trend chart's axes (already localized).
public struct TrendChartLabels: Sendable, Equatable {
    /// The day axis ("Date").
    public var date: String
    /// The value axis ("Tokens", "Cost").
    public var value: String

    public init(date: String = "", value: String = "") {
        self.date = date
        self.value = value
    }
}

/// Day-axis ticks: every n-th category from the first, so at most
/// `maxLabels` labels show (the desktop's `axisEvery`, sized for a phone).
private func axisCategories(_ keys: [String], maxLabels: Int) -> [String] {
    guard !keys.isEmpty else { return [] }
    let every = max(1, Int((Double(keys.count) / Double(max(1, maxLabels))).rounded(.up)))
    return keys.enumerated().compactMap { $0.offset % every == 0 ? $0.element : nil }
}

/// Scrubbing selects a day only when the caller holds a selection; without
/// one the chart takes no gesture, so it can sit inside a link or a scroll
/// view (and in widgets).
private struct TrendSelection: ViewModifier {
    let selection: Binding<String?>?

    func body(content: Content) -> some View {
        if let selection {
            content.chartXSelection(value: selection)
        } else {
            content
        }
    }
}

/// Faint value grid lines with formatted ticks on the leading edge, and
/// formatted day labels at `dayValues`.
private struct TrendAxes: ViewModifier {
    let showsAxes: Bool
    let dayValues: [String]
    let axisValue: (Double) -> String
    let dateLabel: (String) -> String

    func body(content: Content) -> some View {
        if showsAxes {
            content
                .chartXAxis {
                    AxisMarks(values: dayValues) { value in
                        AxisValueLabel {
                            if let key = value.as(String.self) {
                                Text(verbatim: dateLabel(key))
                            }
                        }
                        .foregroundStyle(TMTheme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.white.opacity(0.07))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(verbatim: axisValue(number))
                            }
                        }
                        .foregroundStyle(TMTheme.muted)
                    }
                }
        } else {
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }
}

/// Stacked daily bars: one bar per day, one segment per tool or model, the
/// biggest key at the bottom (`TrendBarsModel.keys` order) and the top
/// segment's top corners rounded, as the dashboard draws them.
public struct TrendBarsChart: View {
    private let model: TrendBarsModel
    private let selection: Binding<String?>?
    private let color: (String) -> Color
    private let seriesName: (String) -> String
    private let axisValue: (Double) -> String
    private let dateLabel: (String) -> String
    private let showsAxes: Bool
    private let maxDateLabels: Int
    private let labels: TrendChartLabels

    /// - Parameters:
    ///   - selection: the selected day; other bars dim. Scrubbing sets it;
    ///     nil takes no gesture.
    ///   - color: a stack key's colour (`VendorColor.color(for:palette:)` for
    ///     tools, `VendorColor.model(_:palette:)` for models).
    ///   - seriesName: a stack key's display name, for VoiceOver.
    ///   - maxDateLabels: at most this many day labels on the axis.
    public init(
        model: TrendBarsModel,
        selection: Binding<String?>? = nil,
        color: @escaping (String) -> Color,
        seriesName: @escaping (String) -> String = { $0 },
        axisValue: @escaping (Double) -> String,
        dateLabel: @escaping (String) -> String,
        showsAxes: Bool = true,
        maxDateLabels: Int = 6,
        labels: TrendChartLabels = TrendChartLabels()
    ) {
        self.model = model
        self.selection = selection
        self.color = color
        self.seriesName = seriesName
        self.axisValue = axisValue
        self.dateLabel = dateLabel
        self.showsAxes = showsAxes
        self.maxDateLabels = maxDateLabels
        self.labels = labels
    }

    public var body: some View {
        let selected = selection?.wrappedValue
        let rank = Dictionary(model.keys.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        Chart {
            ForEach(model.bars) { bar in
                let segments = Self.stacked(bar, rank: rank)
                ForEach(Array(segments.enumerated()), id: \.element.key) { index, segment in
                    let radius: CGFloat = index == segments.count - 1 ? 3 : 0
                    BarMark(
                        x: .value(labels.date, bar.date),
                        y: .value(labels.value, segment.value),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(color(segment.key))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous))
                    .opacity(selected == nil || selected == bar.date ? 1 : 0.4)
                    .accessibilityLabel(dateLabel(bar.date))
                    .accessibilityValue([seriesName(segment.key), axisValue(segment.value)].joined(separator: " "))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .modifier(TrendSelection(selection: selection))
        .modifier(TrendAxes(
            showsAxes: showsAxes,
            dayValues: axisCategories(model.bars.map(\.date), maxLabels: maxDateLabels),
            axisValue: axisValue,
            dateLabel: dateLabel
        ))
    }

    /// A bar's positive segments in legend order (`rank`: key → position in
    /// `model.keys`), so every bar stacks the same keys in the same order.
    private static func stacked(_ bar: TrendBar, rank: [String: Int]) -> [TrendBarSegment] {
        bar.segments
            .filter { $0.value > 0 && $0.value.isFinite }
            .enumerated()
            .sorted { (rank[$0.element.key] ?? Int.max, $0.offset) < (rank[$1.element.key] ?? Int.max, $1.offset) }
            .map(\.element)
    }
}

/// The smooth area line (Home "Trend"): the desktop's Catmull-Rom line
/// (`areaLineChart(curve: true)`, 1/6 tension) over a fading fill of its
/// colour. Swift Charts places the days and scales the values; the curve is
/// drawn from those positions with `TrendSeriesBuilder.linePath`, so it has
/// the same shape as the Overview trend; no built-in interpolation draws
/// that curve exactly (`.catmullRom` bends differently around spikes).
public struct TrendAreaLineChart: View {
    private let points: [TrendLinePoint]
    private let selection: Binding<String?>?
    private let color: Color
    private let lineWidth: CGFloat
    private let axisValue: (Double) -> String
    private let dateLabel: (String) -> String
    private let showsAxes: Bool
    private let maxDateLabels: Int
    private let labels: TrendChartLabels

    /// - Parameters:
    ///   - selection: the selected day, marked with a rule and a point.
    ///     Scrubbing sets it; nil takes no gesture.
    ///   - showsAxes: false draws the bare sparkline of the Home module.
    public init(
        points: [TrendLinePoint],
        selection: Binding<String?>? = nil,
        color: Color = TMTheme.chartBlue,
        lineWidth: CGFloat = 2,
        axisValue: @escaping (Double) -> String,
        dateLabel: @escaping (String) -> String,
        showsAxes: Bool = true,
        maxDateLabels: Int = 6,
        labels: TrendChartLabels = TrendChartLabels()
    ) {
        self.points = points
        self.selection = selection
        self.color = color
        self.lineWidth = lineWidth
        self.axisValue = axisValue
        self.dateLabel = dateLabel
        self.showsAxes = showsAxes
        self.maxDateLabels = maxDateLabels
        self.labels = labels
    }

    public var body: some View {
        let selectedPoint = selection?.wrappedValue.flatMap { key in points.first { $0.date == key } }
        Chart {
            ForEach(points) { point in
                // Invisible: it places the day, sets the scales and reads the
                // day to VoiceOver; the curve is drawn behind it.
                LineMark(
                    x: .value(labels.date, point.date),
                    y: .value(labels.value, point.value)
                )
                .foregroundStyle(Color.clear)
                .accessibilityLabel(dateLabel(point.date))
                .accessibilityValue(axisValue(point.value))
            }
            if let selectedPoint {
                RuleMark(x: .value(labels.date, selectedPoint.date))
                    .foregroundStyle(TMTheme.text.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                PointMark(
                    x: .value(labels.date, selectedPoint.date),
                    y: .value(labels.value, selectedPoint.value)
                )
                .foregroundStyle(color)
                .symbolSize(36)
                .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let plot = proxy.plotFrame {
                    curve(plot: geometry[plot], size: geometry.size, proxy: proxy)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .modifier(TrendSelection(selection: selection))
        .modifier(TrendAxes(
            showsAxes: showsAxes,
            dayValues: axisCategories(points.map(\.date), maxLabels: maxDateLabels),
            axisValue: axisValue,
            dateLabel: dateLabel
        ))
    }

    /// The line and its fill, at the positions the chart gave the days.
    private func curve(plot: CGRect, size: CGSize, proxy: ChartProxy) -> some View {
        let placed = points.compactMap { point -> TrendPlotPoint? in
            guard let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value) else { return nil }
            return TrendPlotPoint(x: Double(plot.minX + x), y: Double(plot.minY + y))
        }
        let baseline = Double(plot.minY + (proxy.position(forY: 0.0) ?? plot.height))
        // The fill fades over the plot area, as the area mark did.
        let fade = LinearGradient(
            colors: [color.opacity(0.22), color.opacity(0)],
            startPoint: UnitPoint(x: 0.5, y: size.height > 0 ? plot.minY / size.height : 0),
            endPoint: UnitPoint(x: 0.5, y: size.height > 0 ? plot.maxY / size.height : 1)
        )
        return ZStack {
            Path(trendElements: TrendSeriesBuilder.areaPath(through: placed, baseline: baseline))
                .fill(fade)
            Path(trendElements: TrendSeriesBuilder.linePath(through: placed))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The K-line: one candle per bucket of days, green when it closed at or
/// above its open, red below; the wick spans the bucket's quietest to
/// busiest day.
public struct TrendCandleChart: View {
    private let candles: [TrendCandle]
    private let selection: Binding<String?>?
    private let axisValue: (Double) -> String
    private let dateLabel: (String) -> String
    private let showsAxes: Bool
    private let maxDateLabels: Int
    private let bodyWidthRatio: Double
    private let labels: TrendChartLabels
    private let candleValue: ((TrendCandle) -> String)?

    /// - Parameters:
    ///   - selection: the selected candle's `key` (its first day); others
    ///     dim. Scrubbing sets it; nil takes no gesture.
    ///   - dateLabel: formats a candle's first day for the axis and VoiceOver.
    ///   - bodyWidthRatio: body width as a share of the candle's slot (the
    ///     dashboard leaves a 40 % gap).
    ///   - candleValue: a candle's VoiceOver value (e.g. "open …, close …");
    ///     nil reads its closing value.
    public init(
        candles: [TrendCandle],
        selection: Binding<String?>? = nil,
        axisValue: @escaping (Double) -> String,
        dateLabel: @escaping (String) -> String,
        showsAxes: Bool = true,
        maxDateLabels: Int = 6,
        bodyWidthRatio: Double = 0.6,
        labels: TrendChartLabels = TrendChartLabels(),
        candleValue: ((TrendCandle) -> String)? = nil
    ) {
        self.candles = candles
        self.selection = selection
        self.axisValue = axisValue
        self.dateLabel = dateLabel
        self.showsAxes = showsAxes
        self.maxDateLabels = maxDateLabels
        self.bodyWidthRatio = min(1, max(0.05, bodyWidthRatio))
        self.labels = labels
        self.candleValue = candleValue
    }

    public var body: some View {
        let selected = selection?.wrappedValue
        Chart {
            ForEach(candles) { candle in
                let tint = candle.up ? TMTheme.candleUp : TMTheme.candleDown
                let opacity = selected == nil || selected == candle.key ? 1.0 : 0.4
                RuleMark(
                    x: .value(labels.date, candle.key),
                    yStart: .value(labels.value, candle.low),
                    yEnd: .value(labels.value, candle.high)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .opacity(opacity)
                .accessibilityHidden(true)
                if candle.open == candle.close {
                    // A flat bucket still shows a body, 1.5 pt tall (the
                    // dashboard's 1 px minimum).
                    RectangleMark(
                        x: .value(labels.date, candle.key),
                        y: .value(labels.value, candle.close),
                        width: .ratio(bodyWidthRatio),
                        height: .fixed(1.5)
                    )
                    .foregroundStyle(tint)
                    .opacity(opacity)
                    .accessibilityLabel(dateLabel(candle.key))
                    .accessibilityValue(spokenValue(of: candle))
                } else {
                    RectangleMark(
                        x: .value(labels.date, candle.key),
                        yStart: .value(labels.value, min(candle.open, candle.close)),
                        yEnd: .value(labels.value, max(candle.open, candle.close)),
                        width: .ratio(bodyWidthRatio)
                    )
                    .foregroundStyle(tint)
                    .cornerRadius(1)
                    .opacity(opacity)
                    .accessibilityLabel(dateLabel(candle.key))
                    .accessibilityValue(spokenValue(of: candle))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .modifier(TrendSelection(selection: selection))
        .modifier(TrendAxes(
            showsAxes: showsAxes,
            dayValues: axisCategories(candles.map(\.key), maxLabels: maxDateLabels),
            axisValue: axisValue,
            dateLabel: dateLabel
        ))
    }

    private func spokenValue(of candle: TrendCandle) -> String {
        candleValue?(candle) ?? axisValue(candle.close)
    }
}
#endif
