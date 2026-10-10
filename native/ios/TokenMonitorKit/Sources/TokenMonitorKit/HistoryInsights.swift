import Foundation

// The figures around the Activity mosaic and the Trends charts: the stat
// cards (`usageCharts.js` `statsCards`), the active-days chip
// (`app.js` `renderHomeTrendsModule`), the Home trend line and its peak
// (`homeOverview.js` `homeTrendSummary`, `longRangePeakDayTokens`,
// `activityStatsForPeriod`) and the top tools and models from History
// (`dashboard.js` `renderBreakdown`). Numbers only; targets label them.

/// The stat cards, in the desktop's order.
public enum StatCardKey: String, Sendable, CaseIterable, Identifiable {
    case totalTokens
    case totalCost
    case activeDays
    case currentStreak
    case activeTimeMs
    case peakDayTokens
    case favoriteModel
    case messages

    public var id: String { rawValue }
}

/// A stat card's value, by kind (`STAT_CARDS[].kind`).
public enum StatCardValue: Sendable, Hashable {
    case tokens(Int)
    /// The known cost; `unpricedTokens` > 0 with no known cost reads "—", and
    /// any unpriced tokens add the `usage.excludedFromCost` note.
    case cost(usd: Double, unpricedTokens: Int?)
    case days(Int)
    case duration(milliseconds: Double)
    /// nil when History has no models (the desktop shows "—").
    case model(String?)
    case count(Int)
}

public struct StatCard: Sendable, Hashable, Identifiable {
    public var key: StatCardKey
    public var value: StatCardValue

    public var id: StatCardKey { key }

    public init(key: StatCardKey, value: StatCardValue) {
        self.key = key
        self.value = value
    }
}

public enum StatCards {
    /// `statsCards(summary)` (`usageCharts.js:291-312`): total tokens, total
    /// cost, active days, current streak, active time, peak day, favourite
    /// model, messages.
    public static func cards(summary: HistorySummary) -> [StatCard] {
        StatCardKey.allCases.map { key in
            let value: StatCardValue
            switch key {
            case .totalTokens: value = .tokens(summary.totalTokens)
            case .totalCost: value = .cost(usd: summary.totalCost, unpricedTokens: summary.unpricedTokens)
            case .activeDays: value = .days(summary.activeDays)
            case .currentStreak: value = .days(summary.currentStreak)
            case .activeTimeMs: value = .duration(milliseconds: summary.activeTimeMs)
            case .peakDayTokens: value = .tokens(summary.peakDayTokens)
            case .favoriteModel: value = .model(summary.favoriteModel.flatMap { $0.isEmpty ? nil : $0 })
            case .messages: value = .count(summary.messages)
            }
            return StatCard(key: key, value: value)
        }
    }

    /// `formatDurationCompact`'s parts: whole minutes (rounded), split into
    /// hours and minutes; targets render "2h 5m" / "5m" / "0m".
    public static func durationParts(milliseconds: Double) -> (hours: Int, minutes: Int) {
        let totalMinutes = max(0, clampedInt(JSCompat.round((milliseconds.isFinite ? milliseconds : 0) / 60_000)))
        return (totalMinutes / 60, totalMinutes % 60)
    }
}

public enum ActiveDays {
    /// The Home active-days chip (`homeActiveDaysWindow`): "Last 12 months"
    /// counts the drawn grid's days with tokens; "All time" is the History
    /// summary's figure, else the grid's count.
    public static func count(window: ActiveDaysWindow, summary: HistorySummary?, grid: HeatmapGrid) -> Int {
        switch window {
        case .year: return grid.activeDayCount
        case .all: return summary?.activeDays ?? grid.activeDayCount
        }
    }
}

/// `activityStatsForPeriod`'s result.
public struct HistoryActivityStats: Sendable, Hashable {
    public var activeDays: Int
    public var currentStreak: Int
    public var activeTimeMs: Double
    public var peakDayTokens: Int

    public init(activeDays: Int, currentStreak: Int, activeTimeMs: Double, peakDayTokens: Int) {
        self.activeDays = activeDays
        self.currentStreak = currentStreak
        self.activeTimeMs = activeTimeMs
        self.peakDayTokens = peakDayTokens
    }
}

/// The Home trend line (`app.js` `renderHomeTrendsModule`).
public struct HomeTrend: Sendable, Hashable {
    public var points: [TrendLinePoint]
    /// The busiest day on the line (`homeTrendSummary().peak`).
    public var peak: Int
    /// First, middle and last day of the line, for the axis
    /// (`homeTrendSummary().dates`); empty without points.
    public var axisDates: [String]
    /// The "Peak {value}" figure: the History summary's peak or the busiest
    /// supplied day, whichever is larger (`longRangePeakDayTokens`).
    public var longRangePeak: Int

    public init(points: [TrendLinePoint], peak: Int, axisDates: [String], longRangePeak: Int) {
        self.points = points
        self.peak = peak
        self.axisDates = axisDates
        self.longRangePeak = longRangePeak
    }
}

/// One row of the top tools / models from History.
public struct HistoryBreakdownRow: Sendable, Hashable, Identifiable {
    /// Client id or model name.
    public var key: String
    public var tokens: Int
    /// Share of all History tokens, 0…100.
    public var percent: Double
    /// `percent` as the desktop prints it (one decimal, `toFixed(1)`).
    public var percentLabel: String
    /// Bar fill relative to the first (largest) row, 0…1.
    public var fractionOfMax: Double

    public var id: String { key }

    public init(key: String, tokens: Int, percent: Double, percentLabel: String, fractionOfMax: Double) {
        self.key = key
        self.tokens = tokens
        self.percent = percent
        self.percentLabel = percentLabel
        self.fractionOfMax = fractionOfMax
    }
}

public enum HistoryBreakdown {
    /// The dashboard's tool column (`renderBreakdown`): tokens per tool over
    /// `daily` (`antigravity-cli` already folded by decoding), the `limit`
    /// largest (zero rows dropped; equal totals by name), with the share of
    /// all `daily` tokens.
    public static func topClients(daily: [HubHistoryDay], limit: Int = 5) -> [HistoryBreakdownRow] {
        top(daily: daily, limit: limit) { $0.perClient }
    }

    /// The dashboard's model column.
    public static func topModels(daily: [HubHistoryDay], limit: Int = 5) -> [HistoryBreakdownRow] {
        top(daily: daily, limit: limit) { $0.perModel }
    }

    private static func top(daily: [HubHistoryDay], limit: Int, buckets: (HubHistoryDay) -> [String: HistoryBucket]) -> [HistoryBreakdownRow] {
        var totals: [String: Int] = [:]
        var grandTotal = 0
        for day in daily {
            for (key, bucket) in buckets(day) {
                totals[key, default: 0] += bucket.tokens
            }
            grandTotal += day.tokens
        }
        let rows = totals.filter { $0.value > 0 }.sorted { left, right in
            left.value != right.value ? left.value > right.value : left.key < right.key
        }.prefix(max(0, limit))
        let maxValue = rows.first?.value ?? 0
        return rows.map { key, tokens in
            let percent = grandTotal > 0 ? Double(tokens) / Double(grandTotal) * 100 : 0
            return HistoryBreakdownRow(
                key: key,
                tokens: tokens,
                percent: percent,
                percentLabel: JSCompat.toFixed(percent, 1),
                fractionOfMax: maxValue > 0 ? Double(tokens) / Double(maxValue) : 0
            )
        }
    }
}

public enum HistoryInsights {
    /// The Home trend's length in days.
    public static let homeTrendDays = 45

    /// The Home "Trend": the last `days` calendar days ending at `todayKey`
    /// of `daily` (already patched with live today), zero-filled, as a token
    /// line, with its axis dates and the long-range peak (`summary`'s peak or
    /// the busiest row of `daily`). The desktop takes the last 45 History
    /// rows instead, which skips days without usage; here every calendar day
    /// is on the line, as on the Trends charts.
    public static func homeTrend(
        daily: [HubHistoryDay],
        todayKey: String,
        summary: HistorySummary?,
        days: Int = homeTrendDays
    ) -> HomeTrend {
        let rows: [HubHistoryDay]
        if let today = CivilDay.normalized(todayKey), let start = CivilDay.adding(-(max(1, days) - 1), to: today) {
            rows = HistorySeries.fill(daily, from: start, through: today)
        } else {
            rows = []
        }
        let points = TrendSeriesBuilder.line(days: rows, metric: .tokens)
        let line = trendSummary(points: points)
        return HomeTrend(
            points: points,
            peak: line.peak,
            axisDates: line.axisDates,
            longRangePeak: longRangePeakDayTokens(summary: summary, daily: daily)
        )
    }

    /// `homeTrendSummary(points)`: the busiest point and the first, middle
    /// (`floor((n - 1) / 2)`) and last dates.
    public static func trendSummary(points: [TrendLinePoint]) -> (peak: Int, axisDates: [String]) {
        let peak = points.reduce(0) { max($0, clampedInt(max(0, $1.value))) }
        guard let first = points.first, let last = points.last else { return (peak, []) }
        return (peak, [first.date, points[(points.count - 1) / 2].date, last.date])
    }

    /// `longRangePeakDayTokens({historySummary, daily})`.
    public static func longRangePeakDayTokens(summary: HistorySummary?, daily: [HubHistoryDay]) -> Int {
        max(0, summary?.peakDayTokens ?? 0, daily.reduce(0) { max($0, $1.tokens) })
    }

    /// `activityStatsForPeriod`: active days and current streak are always
    /// the History summary's; active time and peak follow the selection — a
    /// ready fixed range's own figures, all History for all time, else the
    /// rows of today's day (today) or month (month) in `daily`.
    public static func activityStats(
        selection: PeriodSelection,
        fixedRange: FixedRangeSnapshot?,
        daily: [HubHistoryDay],
        summary: HistorySummary?,
        todayKey: String
    ) -> HistoryActivityStats {
        let activeDays = summary?.activeDays ?? 0
        let streak = summary?.currentStreak ?? 0
        if let fixedRange, fixedRange.isReady {
            return HistoryActivityStats(
                activeDays: activeDays,
                currentStreak: streak,
                activeTimeMs: fixedRange.summary.activeTimeMs,
                peakDayTokens: fixedRange.summary.peakDayTokens
            )
        }
        if selection == .allTime {
            return HistoryActivityStats(
                activeDays: activeDays,
                currentStreak: streak,
                activeTimeMs: summary?.activeTimeMs ?? 0,
                peakDayTokens: summary?.peakDayTokens ?? 0
            )
        }
        let day = String(todayKey.prefix(10))
        let month = String(day.prefix(7))
        let selected = daily.filter { selection == .today ? $0.date == day : $0.date.hasPrefix(month) }
        return HistoryActivityStats(
            activeDays: activeDays,
            currentStreak: streak,
            activeTimeMs: selected.reduce(0) { $0 + $1.activeTimeMs },
            peakDayTokens: selected.reduce(0) { max($0, $1.tokens) }
        )
    }
}
