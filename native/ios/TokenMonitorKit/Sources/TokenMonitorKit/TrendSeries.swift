import Foundation

// The Trends charts and the Home trend line, ported from
// `src/electron/renderer/usageCharts.js` (`dailyBarsChart`, `candleChart`,
// `areaLineChart`), the K-line bucket rule of `dashboard.js:359-367`, and the
// History series rules of `fixedPeriodRanges.js` (`dailyWithLiveToday`,
// `dailyForRange`). Kit returns values and geometry; targets draw and label.

/// One point of the smooth area line (the Home "Trend").
public struct TrendLinePoint: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var value: Double

    public var id: String { date }

    public init(date: String, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One stacked segment of a trend bar: a tool or model and its value.
public struct TrendBarSegment: Sendable, Hashable, Identifiable {
    /// Client id or model name.
    public var key: String
    public var value: Double

    public var id: String { key }

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

/// One day's stacked bar.
public struct TrendBar: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var total: Double
    public var segments: [TrendBarSegment]

    public var id: String { date }

    public init(date: String, total: Double, segments: [TrendBarSegment]) {
        self.date = date
        self.total = total
        self.segments = segments
    }
}

/// The stacked-bars chart.
public struct TrendBarsModel: Sendable, Hashable {
    /// Stack keys in legend and stacking order.
    public var keys: [String]
    public var bars: [TrendBar]
    public var maxTotal: Double

    public init(keys: [String], bars: [TrendBar], maxTotal: Double) {
        self.keys = keys
        self.bars = bars
        self.maxTotal = maxTotal
    }

    public static let empty = TrendBarsModel(keys: [], bars: [], maxTotal: 0)
}

/// One K-line candle: `days` consecutive calendar days aggregated to OHLC
/// (open = first day, close = last day, high/low = busiest/quietest day).
public struct TrendCandle: Sendable, Hashable, Identifiable {
    /// First day of the bucket, `yyyy-MM-dd`.
    public var key: String
    /// Last day of the bucket.
    public var endKey: String
    /// Days with data in the bucket.
    public var days: Int
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    /// `close >= open`.
    public var up: Bool

    public var id: String { key }

    public init(key: String, endKey: String, days: Int, open: Double, high: Double, low: Double, close: Double, up: Bool) {
        self.key = key
        self.endKey = endKey
        self.days = days
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.up = up
    }
}

/// A point in chart coordinates (points, y down), Foundation-only so the Kit
/// stays free of CoreGraphics.
public struct TrendPlotPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Padding around a chart's plot area.
public struct TrendPlotInsets: Sendable, Hashable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// `areaLineChart`'s defaults.
    public static let areaLine = TrendPlotInsets(top: 6, right: 6, bottom: 8, left: 6)
    /// The Home trend's padding (`app.js` `renderHomeTrendsModule`).
    public static let homeTrend = TrendPlotInsets(top: 4, right: 3, bottom: 4, left: 3)
}

/// One element of an area-line path.
public enum TrendPathElement: Sendable, Hashable {
    case move(TrendPlotPoint)
    case line(TrendPlotPoint)
    case curve(to: TrendPlotPoint, control1: TrendPlotPoint, control2: TrendPlotPoint)
    case close
}

/// `areaLineChart`'s geometry: points scaled into the plot, the stroke path
/// (straight, or the Catmull-Rom curve with 1/6 tension) and the filled area
/// down to the baseline.
public struct AreaLineGeometry: Sendable, Hashable {
    /// One plotted value.
    public struct Point: Sendable, Hashable, Identifiable {
        /// `yyyy-MM-dd`.
        public var date: String
        public var value: Double
        public var x: Double
        public var y: Double

        public var id: String { date }

        public init(date: String, value: Double, x: Double, y: Double) {
            self.date = date
            self.value = value
            self.x = x
            self.y = y
        }
    }

    public var width: Double
    public var height: Double
    /// The plot area: `x`/`y` are its origin, `width`/`height` its size.
    public var plotOrigin: TrendPlotPoint
    public var plotWidth: Double
    public var plotHeight: Double
    /// The value at the plot's top: the largest value, at least 1.
    public var maxValue: Double
    public var points: [Point]
    /// The y of the plot's bottom edge.
    public var baseline: Double
    /// The stroke; empty without points.
    public var line: [TrendPathElement]
    /// The stroke closed down to the baseline; empty without points.
    public var area: [TrendPathElement]

    public init(
        width: Double,
        height: Double,
        plotOrigin: TrendPlotPoint,
        plotWidth: Double,
        plotHeight: Double,
        maxValue: Double,
        points: [Point],
        baseline: Double,
        line: [TrendPathElement],
        area: [TrendPathElement]
    ) {
        self.width = width
        self.height = height
        self.plotOrigin = plotOrigin
        self.plotWidth = plotWidth
        self.plotHeight = plotHeight
        self.maxValue = maxValue
        self.points = points
        self.baseline = baseline
        self.line = line
        self.area = area
    }

    /// The desktop's SVG path text for `elements` (coordinates rounded to two
    /// decimals by `svgRound`), for parity tests and debugging.
    public static func svgPath(_ elements: [TrendPathElement]) -> String {
        func number(_ value: Double) -> String { JSCompat.numberString(JSCompat.round(value * 100) / 100) }
        func pair(_ point: TrendPlotPoint) -> String { "\(number(point.x)),\(number(point.y))" }
        return elements.map { element -> String in
            switch element {
            case .move(let point): return "M" + pair(point)
            case .line(let point): return "L" + pair(point)
            case let .curve(to, control1, control2): return "C\(pair(control1)) \(pair(control2)) \(pair(to))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
}

/// Builds the Trends charts from History rows.
public enum TrendSeriesBuilder {
    /// The value a metric reads from a History day or bucket.
    public static func value(of day: HubHistoryDay, metric: TrendMetricKind) -> Double {
        switch metric {
        case .tokens: return Double(day.tokens)
        case .cost: return day.costUsd
        }
    }

    public static func value(of bucket: HistoryBucket, metric: TrendMetricKind) -> Double {
        switch metric {
        case .tokens: return Double(bucket.tokens)
        case .cost: return bucket.costUsd
        }
    }

    /// `dailyBarsChart(days, {stackBy, metric})` without geometry: one bar per
    /// row (pass calendar-filled rows, `HistorySeries.range`), stacked by the
    /// tool (`perClient`, `antigravity-cli` folded) or model (`perModel`)
    /// buckets. A bar's total is the sum of its buckets, which can be less
    /// than the day's total (usage without a Tool/Model identity). Keys are
    /// ordered by their total over the rows, descending, then by name; each
    /// bar lists a segment for every key its row has, zero values included.
    public static func bars(days: [HubHistoryDay], stack: TrendStack, metric: TrendMetricKind) -> TrendBarsModel {
        func buckets(_ day: HubHistoryDay) -> [String: HistoryBucket] {
            switch stack {
            case .client: return day.perClient
            case .model: return day.perModel
            }
        }
        var keyTotals: [String: Double] = [:]
        for day in days {
            for (key, bucket) in buckets(day) {
                keyTotals[key, default: 0] += value(of: bucket, metric: metric)
            }
        }
        let keys = keyTotals.keys.sorted { left, right in
            let leftTotal = keyTotals[left] ?? 0
            let rightTotal = keyTotals[right] ?? 0
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            return TrendKeyCollation.compare(left, right) < 0
        }
        var maxTotal = 1.0
        let bars = days.map { day -> TrendBar in
            let source = buckets(day)
            // Summed in key order so equal days always give the same total.
            var total = 0.0
            var segments: [TrendBarSegment] = []
            segments.reserveCapacity(source.count)
            for key in keys {
                guard let bucket = source[key] else { continue }
                let segment = value(of: bucket, metric: metric)
                total += segment
                segments.append(TrendBarSegment(key: key, value: segment))
            }
            maxTotal = max(maxTotal, total)
            return TrendBar(date: day.date, total: total, segments: segments)
        }
        return TrendBarsModel(keys: keys, bars: bars, maxTotal: maxTotal)
    }

    /// One point per row, in row order (the line and K-line input).
    public static func line(days: [HubHistoryDay], metric: TrendMetricKind) -> [TrendLinePoint] {
        days.map { TrendLinePoint(date: $0.date, value: value(of: $0, metric: metric)) }
    }

    /// One point per compact row (the History preview fallback).
    public static func line(days: [HistoryDay], metric: TrendMetricKind) -> [TrendLinePoint] {
        days.map { TrendLinePoint(date: $0.date, value: metric == .tokens ? Double($0.tokens) : $0.costUsd) }
    }

    /// The dashboard's K-line bucket size (`dashboard.js:365-367`): 2 days for
    /// a span of at most 10 days, else about one candle per 24 points of plot
    /// width (at least 8 candles), and at least 3 days per candle.
    public static func klineBucketDays(span: Int, plotWidth: Double) -> Int {
        let target = max(8, JSCompat.round(plotWidth / 24))
        return span <= 10 ? 2 : Int(max(3, JSCompat.round(Double(span) / target)))
    }

    /// The calendar span of `points`: whole days from the first to the last
    /// row's date, plus one (0 without points).
    public static func span(of points: [TrendLinePoint]) -> Int {
        guard let first = points.first, let last = points.last,
              let distance = CivilDay.distance(from: first.date, to: last.date) else { return 0 }
        return distance + 1
    }

    /// Candles for the K-line mode at a plot width (points, without axis
    /// padding): `klineBucketDays` over the rows' span, then
    /// `candles(points:bucketDays:)`.
    public static func candles(days: [HubHistoryDay], metric: TrendMetricKind, plotWidth: Double) -> [TrendCandle] {
        let points = line(days: days, metric: metric).sorted { $0.date < $1.date }
        return candles(points: points, bucketDays: klineBucketDays(span: span(of: points), plotWidth: plotWidth))
    }

    /// `candleChart(days, {bucketDays})` without geometry: buckets of
    /// `bucketDays` calendar days counted back from the latest row, so the
    /// newest candle is always a full bucket; open = first row, close = last
    /// row, high/low = busiest/quietest row. Oldest candle first.
    public static func candles(points: [TrendLinePoint], bucketDays: Int) -> [TrendCandle] {
        let rows = points.compactMap { point -> (number: Int, point: TrendLinePoint)? in
            guard let key = CivilDay.normalized(point.date), let number = CivilDay.number(key) else { return nil }
            return (number, TrendLinePoint(date: key, value: point.value.isFinite ? point.value : 0))
        }.sorted { $0.point.date < $1.point.date }
        guard let last = rows.last?.number else { return [] }
        let size = max(1, bucketDays)
        var groups: [Int: [TrendLinePoint]] = [:]
        for row in rows {
            groups[(last - row.number) / size, default: []].append(row.point)
        }
        return groups.keys.sorted(by: >).compactMap { index -> TrendCandle? in
            guard let group = groups[index], let first = group.first, let final = group.last else { return nil }
            let values = group.map(\.value)
            return TrendCandle(
                key: first.date,
                endKey: final.date,
                days: group.count,
                open: first.value,
                high: values.max() ?? 0,
                low: values.min() ?? 0,
                close: final.value,
                up: final.value >= first.value
            )
        }
    }

    /// `areaLineChart(points, {width, height, pad…, curve})`: points spread
    /// evenly across the plot (one point is centred), scaled to the largest
    /// value (at least 1); `curve` draws the Catmull-Rom curve with 1/6
    /// tension (straight with fewer than three points).
    public static func areaLine(
        points: [TrendLinePoint],
        width: Double = 300,
        height: Double = 120,
        insets: TrendPlotInsets = .areaLine,
        curve: Bool = true
    ) -> AreaLineGeometry {
        let values = points.map { $0.value.isFinite ? $0.value : 0 }
        let maxValue = values.reduce(1) { max($0, $1) }
        let innerWidth = max(0, width - insets.left - insets.right)
        let innerHeight = max(0, height - insets.top - insets.bottom)
        let count = points.count
        let plotted = points.indices.map { index -> AreaLineGeometry.Point in
            let x = insets.left + (count <= 1 ? innerWidth / 2 : innerWidth * Double(index) / Double(count - 1))
            let y = insets.top + innerHeight - innerHeight * values[index] / maxValue
            return AreaLineGeometry.Point(date: points[index].date, value: values[index], x: x, y: y)
        }
        let baseline = insets.top + innerHeight
        let line = curve ? smoothPath(plotted) : straightPath(plotted)
        var area: [TrendPathElement] = []
        if let first = plotted.first, let last = plotted.last {
            area = line + [
                .line(TrendPlotPoint(x: last.x, y: baseline)),
                .line(TrendPlotPoint(x: first.x, y: baseline)),
                .close
            ]
        }
        return AreaLineGeometry(
            width: width,
            height: height,
            plotOrigin: TrendPlotPoint(x: insets.left, y: insets.top),
            plotWidth: innerWidth,
            plotHeight: innerHeight,
            maxValue: maxValue,
            points: plotted,
            baseline: baseline,
            line: line,
            area: area
        )
    }

    private static func straightPath(_ points: [AreaLineGeometry.Point]) -> [TrendPathElement] {
        points.enumerated().map { index, point in
            let target = TrendPlotPoint(x: point.x, y: point.y)
            return index == 0 ? .move(target) : .line(target)
        }
    }

    /// `smoothLinePath`: uniform Catmull-Rom through every point as cubic
    /// Béziers, end points repeated.
    private static func smoothPath(_ points: [AreaLineGeometry.Point]) -> [TrendPathElement] {
        guard points.count >= 3 else { return straightPath(points) }
        var path: [TrendPathElement] = [.move(TrendPlotPoint(x: points[0].x, y: points[0].y))]
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]
            path.append(.curve(
                to: TrendPlotPoint(x: p2.x, y: p2.y),
                control1: TrendPlotPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: TrendPlotPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            ))
        }
        return path
    }
}

/// History rows prepared for charts: the live-today patch and calendar fill.
public enum HistorySeries {
    /// `dailyWithLiveToday` (`fixedPeriodRanges.js:252-262`): `today` (a
    /// live `today` period) becomes the row for `todayKey`, replacing the
    /// stored row only when its tokens are at least the stored tokens (so a
    /// late or partial live total never lowers History), or appended when
    /// History has no such row. The live row keeps the stored row's messages
    /// and active time. Rows come back sorted by date. Without a valid key
    /// or a period, `daily` is returned as is.
    public static func dailyWithLiveToday(_ daily: [HubHistoryDay], todayKey: String, today: UsagePeriod?) -> [HubHistoryDay] {
        guard let date = CivilDay.normalized(todayKey), let today else { return daily }
        var rows = daily
        let index = rows.firstIndex { $0.date == date }
        let previous = index.map { rows[$0] }
        let live = liveRow(today, date: date, previous: previous)
        if let index {
            if live.tokens >= rows[index].tokens { rows[index] = live }
        } else {
            rows.append(live)
        }
        return rows.sorted { $0.date < $1.date }
    }

    /// `dailyWithLiveToday` for compact rows (History preview, snapshot): the
    /// live row carries tokens, cost and unpriced tokens and keeps the stored
    /// active time.
    public static func dailyWithLiveToday(_ daily: [HistoryDay], todayKey: String, today: UsagePeriod?) -> [HistoryDay] {
        guard let date = CivilDay.normalized(todayKey), let today else { return daily }
        var rows = daily
        let index = rows.firstIndex { $0.date == date }
        let live = HistoryDay(
            date: date,
            tokens: today.totalTokens,
            costUsd: today.costUsd,
            activeTimeMs: index.flatMap { rows[$0].activeTimeMs },
            unpricedTokens: HistoryWire.unpriced(today.unpricedTokens.map(Double.init), tokens: today.totalTokens)
        )
        if let index {
            if live.tokens >= rows[index].tokens { rows[index] = live }
        } else {
            rows.append(live)
        }
        return rows.sorted { $0.date < $1.date }
    }

    /// `rowFromLivePeriod`: a live period as a History row for `date`. Token
    /// components come from the period's maps (exact when the period says
    /// so; otherwise the remainder is unclassified, or the explicit value
    /// when the wire carried that map). Messages and active time are the
    /// stored row's.
    public static func liveRow(_ period: UsagePeriod, date: String, previous: HubHistoryDay?) -> HubHistoryDay {
        let exact = period.hasExactTokenComponents
        var perClient: [String: HistoryBucket] = [:]
        for (client, entry) in period.clientBreakdown {
            var bucket = liveBucket(entry, exact: exact, explicitUnclassified: period.explicitUnclassified.contains(.clients))
            bucket.messages = previous?.perClient[client]?.messages ?? 0
            let key = HistoryWire.canonicalClient(client)
            if var existing = perClient[key] {
                existing.add(bucket)
                perClient[key] = existing
            } else {
                perClient[key] = bucket
            }
        }
        var perModel: [String: HistoryBucket] = [:]
        for (model, entry) in period.modelBreakdown {
            perModel[model] = liveBucket(entry, exact: exact, explicitUnclassified: period.explicitUnclassified.contains(.models))
        }
        let components = LiveDayComponents(
            total: period.totalTokens,
            cacheRead: period.cacheReadTokens,
            cacheWrite: period.cacheWriteTokens,
            output: period.outputTokens,
            exact: exact,
            unclassified: period.unclassifiedTokens,
            hasExplicitUnclassified: period.explicitUnclassified.contains(.period)
        )
        return HubHistoryDay(
            date: date,
            tokens: period.totalTokens,
            costUsd: period.costUsd,
            messages: previous?.messages ?? 0,
            activeTimeMs: previous?.activeTimeMs ?? 0,
            cacheReadTokens: components.cacheRead,
            cacheWriteTokens: components.cacheWrite,
            outputTokens: components.output,
            unclassifiedTokens: components.unclassified,
            tokenComponentsAvailable: exact,
            unpricedTokens: HistoryWire.unpriced(period.unpricedTokens.map(Double.init), tokens: period.totalTokens),
            perClient: perClient,
            perModel: perModel
        )
    }

    /// The rows from `start` through `end` (`yyyy-MM-dd`), one per calendar
    /// day; a day History omits (no usage) is a zero row
    /// (`dailyForRange` without its today patch). Empty when either key is
    /// invalid or `start` is after `end`.
    public static func fill(_ daily: [HubHistoryDay], from start: String, through end: String) -> [HubHistoryDay] {
        guard let first = CivilDay.number(start), let last = CivilDay.number(end), first <= last else { return [] }
        var byDate: [String: HubHistoryDay] = [:]
        for row in daily where row.date >= start && row.date <= end {
            byDate[row.date] = row
        }
        return (first...last).map { number in
            let key = CivilDay.key(number)
            return byDate[key] ?? HubHistoryDay(date: key, unclassifiedTokens: 0, tokenComponentsAvailable: true)
        }
    }

    /// `fill` for compact rows.
    public static func fill(_ daily: [HistoryDay], from start: String, through end: String) -> [HistoryDay] {
        guard let first = CivilDay.number(start), let last = CivilDay.number(end), first <= last else { return [] }
        var byDate: [String: HistoryDay] = [:]
        for row in daily where row.date >= start && row.date <= end {
            byDate[row.date] = row
        }
        return (first...last).map { number in
            let key = CivilDay.key(number)
            return byDate[key] ?? HistoryDay(date: key, tokens: 0, costUsd: 0)
        }
    }

    /// The first day of a Trends range ending at `todayKey`: N − 1 days
    /// before it, or for `.all` the first History day (`todayKey` when there
    /// is none). Nil for an invalid key.
    public static func rangeStart(_ range: TrendRange, firstDay: String?, todayKey: String) -> String? {
        guard let today = CivilDay.normalized(todayKey) else { return nil }
        guard let count = range.dayCount else {
            return firstDay.flatMap(CivilDay.normalized) ?? today
        }
        return CivilDay.adding(-(max(1, count) - 1), to: today)
    }

    /// A Trends range: N calendar days ending at `todayKey` (`.all`: from the
    /// first row), zero-filled. Pass rows already patched with live today.
    /// Unlike the desktop, which slices the last N History rows
    /// (`clampDaily`), every calendar day is on the axis, so a quiet day
    /// reads as zero instead of disappearing.
    public static func range(_ range: TrendRange, daily: [HubHistoryDay], todayKey: String) -> [HubHistoryDay] {
        guard let start = rangeStart(range, firstDay: daily.first?.date, todayKey: todayKey) else { return [] }
        return fill(daily, from: start, through: todayKey)
    }

    /// `range` for compact rows (the History preview fallback).
    public static func range(_ range: TrendRange, daily: [HistoryDay], todayKey: String) -> [HistoryDay] {
        guard let start = rangeStart(range, firstDay: daily.first?.date, todayKey: todayKey) else { return [] }
        return fill(daily, from: start, through: todayKey)
    }

    /// The History the stats carry (`historyPreview`: the latest 30 days and
    /// 12 months across all devices, no tool or model buckets), for when
    /// `/api/history` is unavailable. Charts built from it cannot stack.
    public static func previewFallback(stats: HubStats) -> HubHistory {
        HubHistory(
            daily: stats.history.map { day in
                HubHistoryDay(
                    date: day.date,
                    tokens: day.tokens,
                    costUsd: day.costUsd,
                    activeTimeMs: day.activeTimeMs ?? 0,
                    unpricedTokens: day.unpricedTokens
                )
            },
            monthly: stats.historyMonths.map { HubHistoryMonth(month: $0.month, tokens: $0.tokens, costUsd: $0.costUsd) },
            summary: stats.historyPreviewSummary.map { summary in
                HistorySummary(
                    totalTokens: summary.totalTokens,
                    totalCost: summary.totalCost,
                    activeDays: summary.activeDays,
                    currentStreak: summary.currentStreak,
                    longestStreak: summary.longestStreak,
                    peakDayTokens: summary.peakDayTokens,
                    favoriteModel: summary.favoriteModel,
                    messages: summary.messages,
                    activeTimeMs: summary.activeTimeMs,
                    unpricedTokens: summary.unpricedTokens
                )
            }
        )
    }

    /// One device's History rows patched with its live today, and the day
    /// its views end on: the device's own current day
    /// (`FixedRanges.deviceDayState`), with today's counters patched into the
    /// day they were counted for. Without day windows the device is read on
    /// `fallbackTodayKey` (the phone's day). `liveToday` overrides the
    /// record's `today` (a fresher `DeviceSummary.detail(.today)`). Nil when
    /// the device shares no History.
    public static func deviceDaily(
        record: DeviceHistoryRecord,
        liveToday: UsagePeriod? = nil,
        now: Date,
        fallbackTodayKey: String
    ) -> DeviceHistoryDaily? {
        guard record.historyAvailable, let history = record.history else { return nil }
        let state = FixedRanges.deviceDayState(record: record, now: now)
        let todayKey = state?.currentKey ?? fallbackTodayKey
        let patchKey = state?.snapshotKey ?? fallbackTodayKey
        return DeviceHistoryDaily(
            daily: dailyWithLiveToday(history.daily, todayKey: patchKey, today: liveToday ?? record.today),
            todayKey: todayKey,
            summary: history.summary
        )
    }

    private static func liveBucket(_ entry: UsageBreakdownEntry, exact: Bool, explicitUnclassified: Bool) -> HistoryBucket {
        let components = LiveDayComponents(
            total: entry.tokens,
            cacheRead: entry.cacheReadTokens ?? 0,
            cacheWrite: entry.cacheWriteTokens ?? 0,
            output: entry.outputTokens ?? 0,
            exact: exact,
            unclassified: entry.unclassifiedTokens ?? 0,
            hasExplicitUnclassified: explicitUnclassified
        )
        return HistoryBucket(
            tokens: entry.tokens,
            costUsd: entry.costUsd,
            messages: 0,
            unpricedTokens: HistoryWire.unpriced(entry.unpricedTokens.map(Double.init), tokens: entry.tokens),
            cacheReadTokens: components.cacheRead,
            cacheWriteTokens: components.cacheWrite,
            outputTokens: components.output,
            unclassifiedTokens: components.unclassified
        )
    }
}

/// One device's patched History rows (`HistorySeries.deviceDaily`).
public struct DeviceHistoryDaily: Sendable, Equatable {
    /// Ascending, live today patched in.
    public var daily: [HubHistoryDay]
    /// The day the device's views end on (`yyyy-MM-dd`).
    public var todayKey: String
    /// The device History's own summary (all of it, not only `daily`).
    public var summary: HistorySummary?

    public init(daily: [HubHistoryDay], todayKey: String, summary: HistorySummary?) {
        self.daily = daily
        self.todayKey = todayKey
        self.summary = summary
    }
}

/// `liveComponentValues` (`fixedPeriodRanges.js`): components clamped into
/// the total in the order cache read, cache write, output; the rest is
/// unclassified unless the period is exact (0) or the wire carried an
/// explicit value (clamped to the rest).
struct LiveDayComponents {
    let cacheRead: Int
    let cacheWrite: Int
    let output: Int
    let unclassified: Int

    init(total rawTotal: Int, cacheRead: Int, cacheWrite: Int, output: Int, exact: Bool, unclassified: Int, hasExplicitUnclassified: Bool) {
        let total = max(0, rawTotal)
        self.cacheRead = min(total, max(0, cacheRead))
        self.cacheWrite = min(total - self.cacheRead, max(0, cacheWrite))
        self.output = min(total - self.cacheRead - self.cacheWrite, max(0, output))
        let remainder = max(0, total - self.cacheRead - self.cacheWrite - self.output)
        if exact {
            self.unclassified = 0
        } else if hasExplicitUnclassified {
            self.unclassified = min(remainder, max(0, unclassified))
        } else {
            self.unclassified = remainder
        }
    }
}

/// `String.prototype.localeCompare` with the default (root) collation, as far
/// as ids need it: case-insensitive first, whitespace and punctuation before
/// digits before letters (punctuation is not ignored), lowercase before
/// uppercase on a tie, then code units. Characters outside ASCII sort after
/// ASCII letters by scalar value — an approximation of ICU, used only to
/// break ties between equal values.
enum TrendKeyCollation {
    private static let asciiOrder: [UInt8: Int] = {
        let order = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789"
        var weights: [UInt8: Int] = [:]
        for (index, byte) in order.utf8.enumerated() { weights[byte] = index }
        let base = order.utf8.count
        for (index, letter) in "abcdefghijklmnopqrstuvwxyz".utf8.enumerated() {
            weights[letter] = base + index
            weights[letter - 32] = base + index
        }
        return weights
    }()

    private static func primary(_ scalar: Unicode.Scalar) -> Int {
        if scalar.isASCII, let weight = asciiOrder[UInt8(scalar.value)] { return weight }
        return 1_000 + Int(scalar.value)
    }

    /// -1, 0 or 1 like `localeCompare`.
    static func compare(_ left: String, _ right: String) -> Int {
        let lhs = Array(left.unicodeScalars)
        let rhs = Array(right.unicodeScalars)
        for (a, b) in zip(lhs, rhs) {
            let weightA = primary(a)
            let weightB = primary(b)
            if weightA != weightB { return weightA < weightB ? -1 : 1 }
        }
        if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
        for (a, b) in zip(lhs, rhs) where a != b {
            let aLower = a.properties.isLowercase
            let bLower = b.properties.isLowercase
            if aLower != bLower { return aLower ? -1 : 1 }
            return a.value < b.value ? -1 : 1
        }
        return 0
    }
}
