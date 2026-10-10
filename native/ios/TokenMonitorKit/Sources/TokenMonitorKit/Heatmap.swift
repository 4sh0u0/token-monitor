import Foundation

// The Activity mosaic: a rolling 12-month, Sunday-first grid of days, ported
// from `src/electron/renderer/usageCharts.js` (`heatmapIntensity`,
// `computeHeatmapIntensities`, `contribHeatmap`, `rollingYearHeatmap`).
// The app (History), the Activity widget (`ActivitySnapshot`) and the tests
// all lay the grid out through `HeatmapBuilder`, so they cannot drift.

/// One day of input to the Activity mosaic.
public struct HeatmapDay: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Tokens with no price, nil when the source does not say.
    public var unpricedTokens: Int?

    public var id: String { date }

    public init(date: String, tokens: Int, costUsd: Double, unpricedTokens: Int? = nil) {
        self.date = date
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
    }

    /// A History day (already patched with live today, see
    /// `HistorySeries.dailyWithLiveToday`).
    public init(_ day: HubHistoryDay) {
        self.init(date: day.date, tokens: day.tokens, costUsd: day.costUsd, unpricedTokens: day.unpricedTokens)
    }

    /// A compact day (History preview, snapshot trend, `ActivitySnapshot`).
    public init(_ day: HistoryDay) {
        self.init(date: day.date, tokens: day.tokens, costUsd: day.costUsd, unpricedTokens: day.unpricedTokens)
    }
}

/// One cell of the mosaic: a calendar day in a Sunday-first week column.
public struct HeatmapCell: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`.
    public var date: String
    /// Week column, 0 = the leftmost (oldest) week.
    public var column: Int
    /// Day of the week, 0 = Sunday … 6 = Saturday, whatever the locale.
    public var row: Int
    /// Intensity 0–4 (0 = no usage).
    public var level: Int
    public var tokens: Int
    public var costUsd: Double
    public var unpricedTokens: Int?

    public var id: String { date }

    public init(date: String, column: Int, row: Int, level: Int, tokens: Int, costUsd: Double, unpricedTokens: Int? = nil) {
        self.date = date
        self.column = column
        self.row = row
        self.level = level
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
    }

    /// The cell detail shows a cost row: some cost is known or some tokens
    /// are unpriced (`showHeatTooltip`, `dashboard.js`).
    public var showsCost: Bool {
        costUsd > 0 || (unpricedTokens ?? 0) > 0
    }

    /// The cost reads "—": tokens are unpriced and no cost is known
    /// (`formatCost`, `dashboard.js`).
    public var hasUnknownCost: Bool {
        (unpricedTokens ?? 0) > 0 && !(costUsd > 0)
    }

    /// Tokens the cost excludes, for the `usage.excludedFromCost` note; nil
    /// when there are none.
    public var excludedFromCostTokens: Int? {
        guard let unpricedTokens, unpricedTokens > 0 else { return nil }
        return unpricedTokens
    }
}

/// A month label, placed on the column that contains the month's 1st.
public struct HeatmapMonthLabel: Sendable, Hashable, Identifiable {
    public var column: Int
    /// `yyyy-MM`; the target formats it as a localized short month.
    public var month: String

    public var id: String { month }

    public init(column: Int, month: String) {
        self.column = column
        self.month = month
    }

    /// The month's number, 1…12 (for a localized `MMM` label), nil when the
    /// key is malformed.
    public var monthNumber: Int? {
        guard month.count == 7, let value = Int(month.suffix(2)), (1...12).contains(value) else { return nil }
        return value
    }

    /// The month's year, nil when the key is malformed.
    public var year: Int? {
        guard month.count == 7 else { return nil }
        return Int(month.prefix(4))
    }
}

/// The laid-out Activity mosaic.
public struct HeatmapGrid: Sendable, Hashable {
    /// Every day from the Sunday on or before `startDate` through `endDate`,
    /// oldest first.
    public var cells: [HeatmapCell]
    /// The number of week columns.
    public var weeks: Int
    public var monthLabels: [HeatmapMonthLabel]
    /// The window's first day (`yyyy-MM-dd`), "" for `.empty`.
    public var startDate: String
    /// The window's last day, normally today (`yyyy-MM-dd`), "" for `.empty`.
    public var endDate: String
    /// What `level` was computed from.
    public var metric: HeatmapMetric

    public init(cells: [HeatmapCell], weeks: Int, monthLabels: [HeatmapMonthLabel], startDate: String, endDate: String, metric: HeatmapMetric) {
        self.cells = cells
        self.weeks = weeks
        self.monthLabels = monthLabels
        self.startDate = startDate
        self.endDate = endDate
        self.metric = metric
    }

    public static let empty = HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: "", endDate: "", metric: .cost)

    /// The cell for a `yyyy-MM-dd` day, nil outside the grid.
    public func cell(on date: String) -> HeatmapCell? {
        guard let first = cells.first,
              let firstDay = CivilDay.number(first.date),
              let day = CivilDay.number(date) else { return nil }
        let index = day - firstDay
        guard cells.indices.contains(index), cells[index].date == date else { return nil }
        return cells[index]
    }

    /// Days in the grid with tokens — the Home active-days chip's
    /// "Last 12 months" figure (it counts every drawn cell, including the
    /// leading days of the first week).
    public var activeDayCount: Int {
        cells.reduce(0) { $0 + ($1.tokens > 0 ? 1 : 0) }
    }

    /// The most recent `count` week columns (the medium Activity widget),
    /// re-based so the first kept column is 0. Month labels outside the kept
    /// columns are dropped; levels are unchanged.
    public func trailing(weeks count: Int) -> HeatmapGrid {
        guard count < weeks else { return self }
        guard count > 0 else {
            return HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: endDate, endDate: endDate, metric: metric)
        }
        let offset = weeks - count
        let kept = cells.filter { $0.column >= offset }.map { cell -> HeatmapCell in
            var moved = cell
            moved.column -= offset
            return moved
        }
        let labels = monthLabels.filter { $0.column >= offset }.map {
            HeatmapMonthLabel(column: $0.column - offset, month: $0.month)
        }
        let start = kept.first.map { max($0.date, startDate) } ?? endDate
        return HeatmapGrid(cells: kept, weeks: count, monthLabels: labels, startDate: start, endDate: endDate, metric: metric)
    }
}

/// The name the Activity widget's contract (`ActivitySnapshot`) uses for the
/// mosaic; the same type as `HeatmapGrid`.
public typealias HeatmapModel = HeatmapGrid

/// Lays out the Activity mosaic exactly as the desktop does.
public enum HeatmapBuilder {
    /// The months a rolling year spans: the window starts on the 1st of the
    /// month 11 months before today, so it shows 12 distinct months.
    public static let rollingYearMonths = 12

    /// `heatmapIntensity` (`usageCharts.js:109-113`): 4 / 3 / 2 / 1 for a
    /// ratio to `max` of ≥ .75 / ≥ .5 / ≥ .25 / > 0, else 0 (also when
    /// `max` is not positive).
    public static func intensity(value: Double, max: Double) -> Int {
        guard max.isFinite, max > 0 else { return 0 }
        let ratio = (value.isFinite ? value : 0) / max
        if ratio >= 0.75 { return 4 }
        if ratio >= 0.5 { return 3 }
        if ratio >= 0.25 { return 2 }
        return ratio > 0 ? 1 : 0
    }

    /// The value a metric reads from a day.
    public static func value(of day: HeatmapDay, metric: HeatmapMetric) -> Double {
        switch metric {
        case .tokens: return Double(day.tokens)
        case .cost: return day.costUsd.isFinite ? day.costUsd : 0
        }
    }

    /// The intensity scale's maximum: the largest value over every supplied
    /// day (`computeHeatmapIntensities`), not only the drawn window, so a
    /// busy day just outside the year still sets the scale as on the desktop.
    public static func maximum(of days: [HeatmapDay], metric: HeatmapMetric) -> Double {
        days.reduce(0) { Swift.max($0, value(of: $1, metric: metric)) }
    }

    /// The rolling window's first day for `todayKey`: the 1st of the month
    /// 11 months back (`rollingYearHeatmap`), nil for an invalid key.
    public static func rollingYearStart(todayKey: String) -> String? {
        guard let today = CivilDay.parts(todayKey) else { return nil }
        let monthIndex = today.year * 12 + (today.month - 1) - (rollingYearMonths - 1)
        let year = monthIndex >= 0 ? monthIndex / 12 : (monthIndex - 11) / 12
        return CivilDay.key(year: year, month: monthIndex - year * 12 + 1, day: 1)
    }

    /// The Home / dashboard Activity mosaic (`rollingYearHeatmap(points,
    /// {endDate: todayKey})` after `computeHeatmapIntensities(points)`):
    /// Sunday-first week columns from the Sunday on or before the window's
    /// first day through `todayKey`, levels scaled to the largest value over
    /// every supplied day. `days` should already carry the live today
    /// (`HistorySeries.dailyWithLiveToday`).
    public static func rollingYear(days: [HeatmapDay], metric: HeatmapMetric, todayKey: String) -> HeatmapGrid {
        guard let end = CivilDay.normalized(todayKey), let start = rollingYearStart(todayKey: end) else {
            return HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: "", endDate: "", metric: metric)
        }
        return grid(days: days, metric: metric, startDate: start, endDate: end)
    }

    /// `rollingYear(days:metric:todayKey:)` over History rows.
    public static func rollingYear(daily: [HubHistoryDay], metric: HeatmapMetric, todayKey: String) -> HeatmapGrid {
        rollingYear(days: daily.map(HeatmapDay.init), metric: metric, todayKey: todayKey)
    }

    /// `contribHeatmap(points, {startDate, endDate})`: every day from the
    /// Sunday on or before `startDate` through `endDate`, a month label on
    /// each column holding a 1st. Levels use `maxValue`, else the largest
    /// value over every supplied day.
    public static func grid(
        days: [HeatmapDay],
        metric: HeatmapMetric,
        startDate: String,
        endDate: String,
        maxValue: Double? = nil
    ) -> HeatmapGrid {
        guard let startDay = CivilDay.number(startDate), let endDay = CivilDay.number(endDate) else {
            return HeatmapGrid(cells: [], weeks: 0, monthLabels: [], startDate: "", endDate: "", metric: metric)
        }
        let scale = maxValue ?? maximum(of: days, metric: metric)
        var byDate: [String: HeatmapDay] = [:]
        byDate.reserveCapacity(days.count)
        for day in days {
            guard let key = CivilDay.normalized(day.date) else { continue }
            byDate[key] = day
        }
        let first = startDay - CivilDay.weekday(startDay)
        var cells: [HeatmapCell] = []
        var labels: [HeatmapMonthLabel] = []
        if first <= endDay {
            cells.reserveCapacity(endDay - first + 1)
            for number in first...endDay {
                let key = CivilDay.key(number)
                let column = (number - first) / 7
                if key.hasSuffix("-01") {
                    labels.append(HeatmapMonthLabel(column: column, month: String(key.prefix(7))))
                }
                let day = byDate[key]
                cells.append(HeatmapCell(
                    date: key,
                    column: column,
                    row: CivilDay.weekday(number),
                    level: day.map { intensity(value: value(of: $0, metric: metric), max: scale) } ?? 0,
                    tokens: day?.tokens ?? 0,
                    costUsd: day?.costUsd ?? 0,
                    unpricedTokens: day?.unpricedTokens
                ))
            }
        }
        return HeatmapGrid(
            cells: cells,
            weeks: cells.last.map { $0.column + 1 } ?? 0,
            monthLabels: labels,
            startDate: startDate,
            endDate: endDate,
            metric: metric
        )
    }
}

/// `yyyy-MM-dd` keys as proleptic Gregorian day numbers (days since
/// 1970-01-01), with integer arithmetic only: the desktop steps day keys in
/// UTC (`addDaysUTC`), which is calendar-independent date math, and the
/// widgets lay out a year of cells without building `Calendar` dates.
enum CivilDay {
    struct Parts: Hashable {
        var year: Int
        var month: Int
        var day: Int
    }

    /// The parts of a strict `yyyy-MM-dd` key, nil when it is malformed or
    /// not a real date.
    static func parts(_ key: String) -> Parts? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month) else { return nil }
        return Parts(year: year, month: month, day: day)
    }

    /// The valid `yyyy-MM-dd` prefix of `value` (`String(date).slice(0, 10)`
    /// plus validation), else nil.
    static func normalized(_ value: String) -> String? {
        let key = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        return parts(key) == nil ? nil : key
    }

    static func number(_ key: String) -> Int? {
        parts(key).map { number(year: $0.year, month: $0.month, day: $0.day) }
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    static func number(year: Int, month: Int, day: Int) -> Int {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The parts of a day number (`civil_from_days`).
    static func parts(_ number: Int) -> Parts {
        let shifted = number + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return Parts(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    static func key(_ number: Int) -> String {
        let value = parts(number)
        return key(year: value.year, month: value.month, day: value.day)
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        padded(year, 4) + "-" + padded(month, 2) + "-" + padded(day, 2)
    }

    /// 0 = Sunday … 6 = Saturday (`dayOfWeekSun`); 1970-01-01 was a Thursday.
    static func weekday(_ number: Int) -> Int {
        ((number + 4) % 7 + 7) % 7
    }

    /// The day numbers of 0000-01-01 and 9999-12-31: the keys that stay
    /// four-digit years.
    static let firstNumber = number(year: 0, month: 1, day: 1)
    static let lastNumber = number(year: 9999, month: 12, day: 31)

    /// The key `days` after `key` (negative: before), nil for a bad key or a
    /// result outside years 0000–9999 (which also rules out overflow).
    static func adding(_ days: Int, to key: String) -> String? {
        guard let start = number(key) else { return nil }
        let (moved, overflow) = start.addingReportingOverflow(days)
        guard !overflow, moved >= firstNumber, moved <= lastNumber else { return nil }
        return self.key(moved)
    }

    /// Whole days from `start` to `end` (negative when `end` is earlier).
    static func distance(from start: String, to end: String) -> Int? {
        guard let first = number(start), let last = number(end) else { return nil }
        return last - first
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let body = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return value < 0 ? "-" + body : body
    }
}
