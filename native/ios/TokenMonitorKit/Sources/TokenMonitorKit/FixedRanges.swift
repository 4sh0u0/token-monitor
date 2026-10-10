import Foundation

// The fixed ranges WEEK / 7D / 30D (`periodMonthMode`), derived from History
// plus the live today, ported from `src/electron/renderer/fixedPeriodRanges.js`
// (`rangeForSelection`, `fixedPeriodSnapshot`, `derivePeriod`,
// `summaryForDaily`, `deviceDayState`, `fixedPeriodSnapshotFromDevices`).
//
// The aggregate reads `/api/history` with the aggregate live `today` keyed by
// the phone's day; the desktop instead merges every device's History on each
// device's own day keys, which differs only for fleets spanning time zones
// (plan D-FIXEDRANGE). A scoped device uses its `/api/devices` record on its
// own day (`deviceDayState`).

/// An inclusive range of `yyyy-MM-dd` days.
public struct DayKeyRange: Sendable, Hashable {
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// Calendar days in the range, 0 when it is empty or malformed.
    public var dayCount: Int {
        guard let distance = CivilDay.distance(from: start, to: end), distance >= 0 else { return 0 }
        return distance + 1
    }

    public func contains(_ day: String) -> Bool {
        day >= start && day <= end
    }
}

/// Why a fixed range cannot be shown.
public enum FixedRangeUnavailableReason: String, Sendable, Hashable {
    /// History sharing is off.
    case historyDisabled
    /// History is not loaded, the Hub or device does not share it, or a
    /// device's day cannot be placed.
    case historyUnavailable
}

/// `summaryForDaily`: the range's own figures.
public struct RangeSummary: Sendable, Hashable {
    public var activeDays: Int
    /// Consecutive days with usage ending at the range's last day.
    public var currentStreak: Int
    public var activeTimeMs: Double
    public var peakDayTokens: Int

    public init(activeDays: Int = 0, currentStreak: Int = 0, activeTimeMs: Double = 0, peakDayTokens: Int = 0) {
        self.activeDays = activeDays
        self.currentStreak = currentStreak
        self.activeTimeMs = activeTimeMs
        self.peakDayTokens = peakDayTokens
    }

    public static let empty = RangeSummary()
}

/// A fixed range's usage (`fixedPeriodSnapshot`).
public struct FixedRangeSnapshot: Sendable, Equatable {
    public enum Status: Sendable, Hashable {
        /// `period` holds the range's usage.
        case ready
        /// The selection is a Hub period (today, month, all time); read it
        /// from the stats instead.
        case native
        case unavailable(FixedRangeUnavailableReason)
    }

    public var status: Status
    public var selection: PeriodSelection
    /// The days covered; nil unless ready.
    public var range: DayKeyRange?
    /// One row per day of `range`, zero-filled, live today patched in.
    public var daily: [HubHistoryDay]
    public var summary: RangeSummary
    /// The range as a period: totals, components, and the tool and model
    /// breakdowns (`derivePeriod`). Sessions and projects are never
    /// available for a fixed range. Nil unless ready.
    public var period: UsagePeriod?

    public init(
        status: Status,
        selection: PeriodSelection,
        range: DayKeyRange? = nil,
        daily: [HubHistoryDay] = [],
        summary: RangeSummary = .empty,
        period: UsagePeriod? = nil
    ) {
        self.status = status
        self.selection = selection
        self.range = range
        self.daily = daily
        self.summary = summary
        self.period = period
    }

    public var isReady: Bool { status == .ready }

    static func unavailable(_ reason: FixedRangeUnavailableReason, _ selection: PeriodSelection) -> FixedRangeSnapshot {
        FixedRangeSnapshot(status: .unavailable(reason), selection: selection)
    }
}

/// `deviceDayState`: the day a device's views end on and the day its live
/// `today` counters were counted for.
public struct DeviceDayState: Sendable, Hashable {
    /// The device's current local day (`yyyy-MM-dd`).
    public var currentKey: String
    /// The day of the device's last `today` window: `currentKey` while the
    /// window is open, the earlier day once it has ended.
    public var snapshotKey: String

    public init(currentKey: String, snapshotKey: String) {
        self.currentKey = currentKey
        self.snapshotKey = snapshotKey
    }
}

/// The breakdowns a view can ask a fixed range for (`supportsBreakdown`).
public enum FixedRangeBreakdown: String, Sendable, CaseIterable {
    case tool
    case model
    case device
    case session
    case project
}

public enum FixedRanges {
    /// The desktop's `weekStartsOn` (0 = Sunday … 6 = Saturday) for a
    /// `Calendar.firstWeekday` (1 = Sunday … 7 = Saturday); the locale's week
    /// start is `Calendar.current.firstWeekday`.
    public static func weekStart(firstWeekday: Int) -> Int {
        ((firstWeekday - 1) % 7 + 7) % 7
    }

    /// `rangeForSelection`: WEEK runs from the locale's week start through
    /// today, 7D and 30D are the last 7 / 30 days including today. Nil for a
    /// Hub period or an invalid key.
    public static func range(for selection: PeriodSelection, todayKey: String, firstWeekday: Int) -> DayKeyRange? {
        guard let today = CivilDay.normalized(todayKey), let number = CivilDay.number(today) else { return nil }
        switch selection {
        case .week:
            let offset = (CivilDay.weekday(number) - weekStart(firstWeekday: firstWeekday) + 7) % 7
            return DayKeyRange(start: CivilDay.key(number - offset), end: today)
        case .last7:
            return DayKeyRange(start: CivilDay.key(number - 6), end: today)
        case .last30:
            return DayKeyRange(start: CivilDay.key(number - 29), end: today)
        case .today, .month, .allTime:
            return nil
        }
    }

    /// `supportsBreakdown`: a fixed range has tools and models, devices only
    /// when per-device History is loaded, never sessions or projects.
    public static func supports(_ breakdown: FixedRangeBreakdown, selection: PeriodSelection, deviceHistoriesAvailable: Bool = false) -> Bool {
        guard selection.isDerived else { return true }
        switch breakdown {
        case .tool, .model: return true
        case .device: return deviceHistoriesAvailable
        case .session, .project: return false
        }
    }

    /// `deviceDayState(source, {now})`: while the device's `today` window is
    /// open, both keys are its key; after it ended, the current key is `now`'s
    /// day in the device's time zone. Nil when the record has no window, or
    /// the window has ended and the time zone is missing or unknown.
    public static func deviceDayState(record: DeviceHistoryRecord, now: Date) -> DeviceDayState? {
        deviceDayState(todayWindowKey: record.todayWindowKey, todayEndsAt: record.todayEndsAt, timeZone: record.timeZone, now: now)
    }

    /// `deviceDayState` from a stats device's period windows.
    public static func deviceDayState(device: DeviceSummary, now: Date) -> DeviceDayState? {
        deviceDayState(todayWindowKey: device.todayWindowKey, todayEndsAt: device.todayEndsAt, timeZone: device.periodTimeZone, now: now)
    }

    public static func deviceDayState(todayWindowKey: String?, todayEndsAt: Date?, timeZone: String?, now: Date) -> DeviceDayState? {
        guard let key = todayWindowKey.flatMap(CivilDay.normalized), let endsAt = todayEndsAt else { return nil }
        if now < endsAt { return DeviceDayState(currentKey: key, snapshotKey: key) }
        guard let identifier = timeZone?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty,
              let zone = TimeZone(identifier: identifier) else { return nil }
        return DeviceDayState(currentKey: dayKey(for: now, in: zone), snapshotKey: key)
    }

    /// `now`'s calendar day in `timeZone` (`yyyy-MM-dd`).
    public static func dayKey(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return DayKey.string(from: date, calendar: calendar)
    }

    /// `fixedPeriodSnapshot(selection, {daily, todayKey, liveTodayKey,
    /// todayPeriod, historyAvailable, historyEnabled, locale})`: the range
    /// ending at `todayKey`, from `daily` with `today` patched into
    /// `liveTodayKey` (default `todayKey`) by `HistorySeries.dailyWithLiveToday`.
    /// `firstWeekday` is `Calendar.firstWeekday` (WEEK's first day).
    public static func snapshot(
        selection: PeriodSelection,
        daily: [HubHistoryDay],
        todayKey: String,
        liveTodayKey: String? = nil,
        today: UsagePeriod?,
        historyAvailable: Bool,
        historyEnabled: Bool = true,
        firstWeekday: Int
    ) -> FixedRangeSnapshot {
        guard selection.isDerived else { return FixedRangeSnapshot(status: .native, selection: selection) }
        guard historyEnabled else { return .unavailable(.historyDisabled, selection) }
        guard historyAvailable, let range = range(for: selection, todayKey: todayKey, firstWeekday: firstWeekday) else {
            return .unavailable(.historyUnavailable, selection)
        }
        let patched = HistorySeries.dailyWithLiveToday(daily, todayKey: liveTodayKey ?? range.end, today: today)
        let rows = HistorySeries.fill(patched, from: range.start, through: range.end)
        return FixedRangeSnapshot(
            status: .ready,
            selection: selection,
            range: range,
            daily: rows,
            summary: summary(daily: rows),
            period: derivePeriod(daily: rows, range: range)
        )
    }

    /// `fixedPeriodSnapshotFromDevices(selection, [source], {now, locale})`
    /// for one device: its History record (`/api/devices`) on its own day
    /// (`deviceDayState`), with its live `today` (`liveToday`, else the
    /// record's) patched into the day it was counted for. Unavailable when
    /// the device does not share History or its day cannot be placed. A
    /// device without any usage gets an empty range ending on `now`'s day in
    /// `calendar`. `device` (the stats entry) adds its month and all-time
    /// totals to the usage check.
    public static func deviceSnapshot(
        selection: PeriodSelection,
        record: DeviceHistoryRecord,
        device: DeviceSummary? = nil,
        liveToday: UsagePeriod? = nil,
        now: Date,
        firstWeekday: Int,
        calendar: Calendar = .current,
        historyEnabled: Bool = true
    ) -> FixedRangeSnapshot {
        guard selection.isDerived else { return FixedRangeSnapshot(status: .native, selection: selection) }
        guard historyEnabled else { return .unavailable(.historyDisabled, selection) }
        guard record.historyAvailable, let history = record.history else { return .unavailable(.historyUnavailable, selection) }
        let today = liveToday ?? record.today
        guard participates(today: today, device: device, daily: history.daily) else {
            return snapshot(
                selection: selection,
                daily: [],
                todayKey: DayKey.string(from: now, calendar: calendar),
                today: nil,
                historyAvailable: true,
                firstWeekday: firstWeekday
            )
        }
        guard let state = deviceDayState(record: record, now: now) else { return .unavailable(.historyUnavailable, selection) }
        let own = snapshot(
            selection: selection,
            daily: history.daily,
            todayKey: state.currentKey,
            liveTodayKey: state.snapshotKey,
            today: today,
            historyAvailable: true,
            firstWeekday: firstWeekday
        )
        guard own.isReady, let range = own.range else { return own }
        // The desktop merges the selected devices' rows (`mergeSelectedDaily`)
        // and derives the period again from the merged rows.
        let merged = mergeSelectedDaily([own.daily])
        return FixedRangeSnapshot(
            status: .ready,
            selection: selection,
            range: range,
            daily: merged,
            summary: summary(daily: merged),
            period: derivePeriod(daily: merged, range: range)
        )
    }

    /// `summaryForDaily` over a range's rows.
    public static func summary(daily: [HubHistoryDay]) -> RangeSummary {
        var streak = 0
        for row in daily.reversed() {
            guard row.tokens > 0 else { break }
            streak += 1
        }
        return RangeSummary(
            activeDays: daily.reduce(0) { $0 + ($1.tokens > 0 ? 1 : 0) },
            currentStreak: streak,
            activeTimeMs: daily.reduce(0) { $0 + $1.activeTimeMs },
            peakDayTokens: daily.reduce(0) { max($0, $1.tokens) }
        )
    }

    /// `derivePeriod(daily, range)`: the range's rows summed into a period —
    /// totals, cost (6 decimals), unpriced tokens, components (a row or
    /// bucket without an explicit unclassified count is wholly unclassified
    /// unless the row is exact: `HubHistoryDay.resolvedUnclassifiedTokens`,
    /// `HistoryBucket.resolvedUnclassifiedTokens`), and the tool and model
    /// breakdowns. Components are exact only when every row is.
    public static func derivePeriod(daily: [HubHistoryDay], range: DayKeyRange) -> UsagePeriod {
        let rows = HistorySeries.fill(daily, from: range.start, through: range.end)
        var totalTokens = 0
        var cost = 0.0
        var unpriced = 0
        var cacheRead = 0
        var cacheWrite = 0
        var output = 0
        var unclassified = 0
        var clients = BreakdownSums()
        var models = BreakdownSums()
        for row in rows {
            totalTokens += row.tokens
            cost += row.costUsd
            unpriced += row.unpricedTokens ?? 0
            cacheRead += row.cacheReadTokens
            cacheWrite += row.cacheWriteTokens
            output += row.outputTokens
            unclassified += row.resolvedUnclassifiedTokens
            for (client, bucket) in row.perClient {
                clients.add(HistoryWire.canonicalClient(client), bucket)
            }
            for (model, bucket) in row.perModel {
                models.add(model, bucket)
            }
        }
        let clientBreakdown = clients.entries()
        let modelBreakdown = models.entries()
        return UsagePeriod(
            totalTokens: max(0, totalTokens),
            costUsd: rounded6(cost),
            outputTokens: max(0, output),
            cacheReadTokens: max(0, cacheRead),
            cacheWriteTokens: max(0, cacheWrite),
            unclassifiedTokens: max(0, unclassified),
            unpricedTokens: unpriced > 0 ? unpriced : nil,
            hasExactTokenComponents: rows.allSatisfy(\.tokenComponentsAvailable),
            hasCompleteThroughput: false,
            clients: UsagePeriod.shares(
                tokens: clientBreakdown.mapValues { Double($0.tokens) },
                costs: clientBreakdown.mapValues(\.costUsd)
            ) { id, tokens, cost in UsageShare.client(id, tokens: tokens, costUsd: cost) },
            models: UsagePeriod.shares(
                tokens: modelBreakdown.mapValues { Double($0.tokens) },
                costs: modelBreakdown.mapValues(\.costUsd)
            ) { name, tokens, cost in UsageShare.model(name, tokens: tokens, costUsd: cost) },
            clientBreakdown: clientBreakdown,
            modelBreakdown: modelBreakdown,
            explicitUnclassified: .all
        )
    }

    /// `mergeSelectedDaily`: rows of several sources summed per day, with
    /// every unclassified count made explicit (`unclassifiedTokensFor`) and
    /// components exact only when every merged row is. Like the desktop, the
    /// merged rows carry no row-level message count (tool buckets keep theirs).
    static func mergeSelectedDaily(_ sources: [[HubHistoryDay]]) -> [HubHistoryDay] {
        var byDate: [String: HubHistoryDay] = [:]
        for rows in sources {
            for row in rows {
                var target = byDate[row.date] ?? HubHistoryDay(date: row.date, unclassifiedTokens: 0, tokenComponentsAvailable: true)
                target.tokens += row.tokens
                target.costUsd += row.costUsd
                if let count = row.unpricedTokens, count > 0 { target.unpricedTokens = (target.unpricedTokens ?? 0) + count }
                target.activeTimeMs += row.activeTimeMs
                target.cacheReadTokens += row.cacheReadTokens
                target.cacheWriteTokens += row.cacheWriteTokens
                target.outputTokens += row.outputTokens
                target.unclassifiedTokens = (target.unclassifiedTokens ?? 0) + row.resolvedUnclassifiedTokens
                target.tokenComponentsAvailable = target.tokenComponentsAvailable && row.tokenComponentsAvailable
                for (client, bucket) in row.perClient {
                    let key = HistoryWire.canonicalClient(client)
                    target.perClient[key] = mergedBucket(target.perClient[key], bucket, keepsMessages: true)
                }
                for (model, bucket) in row.perModel {
                    target.perModel[model] = mergedBucket(target.perModel[model], bucket, keepsMessages: false)
                }
                byDate[row.date] = target
            }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// `addDailyAttribution` for one bucket.
    private static func mergedBucket(_ existing: HistoryBucket?, _ bucket: HistoryBucket, keepsMessages: Bool) -> HistoryBucket {
        var target = existing ?? HistoryBucket(cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, unclassifiedTokens: 0)
        target.tokens += bucket.tokens
        target.costUsd += bucket.costUsd
        if let count = bucket.unpricedTokens, count > 0 { target.unpricedTokens = (target.unpricedTokens ?? 0) + count }
        target.cacheReadTokens = (target.cacheReadTokens ?? 0) + (bucket.cacheReadTokens ?? 0)
        target.cacheWriteTokens = (target.cacheWriteTokens ?? 0) + (bucket.cacheWriteTokens ?? 0)
        target.outputTokens = (target.outputTokens ?? 0) + (bucket.outputTokens ?? 0)
        target.unclassifiedTokens = (target.unclassifiedTokens ?? 0) + bucket.resolvedUnclassifiedTokens
        if keepsMessages { target.messages += bucket.messages }
        return target
    }

    private static func participates(today: UsagePeriod?, device: DeviceSummary?, daily: [HubHistoryDay]) -> Bool {
        if let today, today.totalTokens > 0 || today.costUsd > 0 { return true }
        if let device {
            for usage in [device.today, device.month, device.allTime] where usage.tokens > 0 || usage.costUsd > 0 {
                return true
            }
        }
        return daily.contains { $0.tokens > 0 || $0.costUsd > 0 }
    }

    /// `Number(value.toFixed(6))`.
    static func rounded6(_ value: Double) -> Double {
        Double(JSCompat.toFixed(value, 6)) ?? value
    }
}

/// Per-key sums for `derivePeriod`'s maps.
private struct BreakdownSums {
    private var tokens: [String: Int] = [:]
    private var costs: [String: Double] = [:]
    private var unpriced: [String: Int] = [:]
    private var cacheReads: [String: Int] = [:]
    private var cacheWrites: [String: Int] = [:]
    private var outputs: [String: Int] = [:]
    private var unclassified: [String: Int] = [:]

    mutating func add(_ key: String, _ bucket: HistoryBucket) {
        guard !key.isEmpty else { return }
        tokens[key, default: 0] += bucket.tokens
        costs[key, default: 0] += bucket.costUsd
        if let count = bucket.unpricedTokens, count > 0 { unpriced[key, default: 0] += count }
        cacheReads[key, default: 0] += bucket.cacheReadTokens ?? 0
        cacheWrites[key, default: 0] += bucket.cacheWriteTokens ?? 0
        outputs[key, default: 0] += bucket.outputTokens ?? 0
        unclassified[key, default: 0] += bucket.resolvedUnclassifiedTokens
    }

    func entries() -> [String: UsageBreakdownEntry] {
        var result: [String: UsageBreakdownEntry] = [:]
        result.reserveCapacity(tokens.count)
        for (key, count) in tokens {
            result[key] = UsageBreakdownEntry(
                tokens: max(0, count),
                costUsd: FixedRanges.rounded6(costs[key] ?? 0),
                unpricedTokens: unpriced[key],
                cacheReadTokens: max(0, cacheReads[key] ?? 0),
                cacheWriteTokens: max(0, cacheWrites[key] ?? 0),
                outputTokens: max(0, outputs[key] ?? 0),
                unclassifiedTokens: max(0, unclassified[key] ?? 0)
            )
        }
        return result
    }
}
