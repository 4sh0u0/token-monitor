import Foundation

// Models for the Hub's full History (`GET /api/history`) and for the
// per-device History carried by `GET /api/devices` records. Both are the shape
// `src/shared/history.js` produces: `{daily, monthly, summary}`. The app reads
// them lazily (they are large); widgets and the watch never do.

/// One `perClient` / `perModel` entry of a History day or month.
public struct HistoryBucket: Sendable, Hashable {
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// User messages; model buckets carry none (0).
    public var messages: Int
    /// Tokens with no price, clamped to `tokens`; nil when there are none.
    public var unpricedTokens: Int?
    /// Token components, nil when the wire leaves them out. Components only
    /// exist for a device's latest 30 days, and monthly buckets carry none.
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?
    public var outputTokens: Int?
    /// nil when the wire leaves the field out, which is not the same as 0:
    /// a bucket without it counts as wholly unclassified
    /// (see `resolvedUnclassifiedTokens`).
    public var unclassifiedTokens: Int?

    public init(
        tokens: Int = 0,
        costUsd: Double = 0,
        messages: Int = 0,
        unpricedTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        outputTokens: Int? = nil,
        unclassifiedTokens: Int? = nil
    ) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.messages = messages
        self.unpricedTokens = unpricedTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.unclassifiedTokens = unclassifiedTokens
    }

    /// The desktop's `unclassifiedTokensFor(bucket)`: the explicit value when
    /// the wire has one, else every token (a bucket has no
    /// `tokenComponentsAvailable` flag to say otherwise). The Hub omits a
    /// tool bucket's `unclassifiedTokens` when it is 0 (model buckets keep
    /// it), so on the desktop's fixed ranges an exact tool bucket still reads
    /// as wholly unclassified; ports reproduce that.
    public var resolvedUnclassifiedTokens: Int {
        unclassifiedTokens ?? tokens
    }

    /// Adds `other` the way the desktop's `foldClientMap` does: every metric
    /// `other` carries is added, and a metric only one side carries is kept.
    public mutating func add(_ other: HistoryBucket) {
        tokens += other.tokens
        costUsd += other.costUsd
        messages += other.messages
        unpricedTokens = Self.sum(unpricedTokens, other.unpricedTokens)
        cacheReadTokens = Self.sum(cacheReadTokens, other.cacheReadTokens)
        cacheWriteTokens = Self.sum(cacheWriteTokens, other.cacheWriteTokens)
        outputTokens = Self.sum(outputTokens, other.outputTokens)
        unclassifiedTokens = Self.sum(unclassifiedTokens, other.unclassifiedTokens)
    }

    private static func sum(_ left: Int?, _ right: Int?) -> Int? {
        guard left != nil || right != nil else { return nil }
        return (left ?? 0) + (right ?? 0)
    }
}

extension HistoryBucket: Decodable {
    private enum CodingKeys: String, CodingKey {
        case tokens, cost, messages, unpricedTokens, cacheReadTokens, cacheWriteTokens, outputTokens, unclassifiedTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tokens = nonNegative(container.lenientInt(.tokens) ?? 0)
        self.init(
            tokens: tokens,
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0),
            messages: nonNegative(container.lenientInt(.messages) ?? 0),
            unpricedTokens: HistoryWire.unpriced(container.lenientDouble(.unpricedTokens), tokens: tokens),
            cacheReadTokens: container.lenientInt(.cacheReadTokens).map(nonNegative),
            cacheWriteTokens: container.lenientInt(.cacheWriteTokens).map(nonNegative),
            outputTokens: container.lenientInt(.outputTokens).map(nonNegative),
            unclassifiedTokens: container.lenientInt(.unclassifiedTokens).map(nonNegative)
        )
    }
}

/// One day of `GET /api/history` `daily[]` (or of a device record's History).
///
/// The wire's `tokenIntensity` / `costIntensity` / `intensity` are not kept:
/// renderers recompute intensity from the rows they actually draw.
public struct HubHistoryDay: Sendable, Hashable, Identifiable {
    /// `yyyy-MM-dd`, in the producing device's local calendar.
    public var date: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    public var messages: Int
    public var activeTimeMs: Double
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var outputTokens: Int
    /// nil when the wire leaves the field out (see `resolvedUnclassifiedTokens`).
    public var unclassifiedTokens: Int?
    /// Every component of the day is exact (`=== true` on the wire).
    public var tokenComponentsAvailable: Bool
    /// Tokens with no price, clamped to `tokens`; nil when there are none.
    public var unpricedTokens: Int?
    /// Tools by client id, `antigravity-cli` folded into `antigravity`.
    public var perClient: [String: HistoryBucket]
    /// Models by model id.
    public var perModel: [String: HistoryBucket]

    public var id: String { date }

    public init(
        date: String,
        tokens: Int = 0,
        costUsd: Double = 0,
        messages: Int = 0,
        activeTimeMs: Double = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        outputTokens: Int = 0,
        unclassifiedTokens: Int? = nil,
        tokenComponentsAvailable: Bool = false,
        unpricedTokens: Int? = nil,
        perClient: [String: HistoryBucket] = [:],
        perModel: [String: HistoryBucket] = [:]
    ) {
        self.date = date
        self.tokens = tokens
        self.costUsd = costUsd
        self.messages = messages
        self.activeTimeMs = activeTimeMs
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.unclassifiedTokens = unclassifiedTokens
        self.tokenComponentsAvailable = tokenComponentsAvailable
        self.unpricedTokens = unpricedTokens
        self.perClient = perClient
        self.perModel = perModel
    }

    /// The desktop's `unclassifiedTokensFor(day)`: the explicit value when the
    /// wire has one, else 0 for an exact day and every token otherwise.
    public var resolvedUnclassifiedTokens: Int {
        unclassifiedTokens ?? (tokenComponentsAvailable ? 0 : tokens)
    }

    /// The day as the compact row the snapshot, preview and Activity widget use.
    public var historyDay: HistoryDay {
        HistoryDay(
            date: date,
            tokens: tokens,
            costUsd: costUsd,
            activeTimeMs: activeTimeMs > 0 ? activeTimeMs : nil,
            unpricedTokens: unpricedTokens
        )
    }
}

extension HubHistoryDay: Decodable {
    private enum CodingKeys: String, CodingKey {
        case date, tokens, cost, messages, activeTimeMs, cacheReadTokens, cacheWriteTokens, outputTokens
        case unclassifiedTokens, tokenComponentsAvailable, unpricedTokens, perClient, perModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = container.lenientString(.date), let date = DayKey.normalized(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "invalid day key")
        }
        let tokens = nonNegative(container.lenientInt(.tokens) ?? 0)
        self.init(
            date: date,
            tokens: tokens,
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0),
            messages: nonNegative(container.lenientInt(.messages) ?? 0),
            activeTimeMs: nonNegative(container.lenientDouble(.activeTimeMs) ?? 0),
            cacheReadTokens: nonNegative(container.lenientInt(.cacheReadTokens) ?? 0),
            cacheWriteTokens: nonNegative(container.lenientInt(.cacheWriteTokens) ?? 0),
            outputTokens: nonNegative(container.lenientInt(.outputTokens) ?? 0),
            unclassifiedTokens: container.lenientInt(.unclassifiedTokens).map(nonNegative),
            tokenComponentsAvailable: container.lenientBool(.tokenComponentsAvailable) ?? false,
            unpricedTokens: HistoryWire.unpriced(container.lenientDouble(.unpricedTokens), tokens: tokens),
            perClient: HistoryWire.clientBuckets(container, .perClient),
            perModel: HistoryWire.buckets(container, .perModel)
        )
    }
}

/// One month of `GET /api/history` `monthly[]` (uncapped, ascending).
public struct HubHistoryMonth: Sendable, Hashable, Identifiable {
    /// `yyyy-MM`.
    public var month: String
    public var tokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    public var activeTimeMs: Double
    /// Tokens with no price, clamped to `tokens`; nil when there are none.
    public var unpricedTokens: Int?
    /// Tools by client id, `antigravity-cli` folded into `antigravity`. Monthly
    /// buckets carry no token components.
    public var perClient: [String: HistoryBucket]
    public var perModel: [String: HistoryBucket]

    public var id: String { month }

    public init(
        month: String,
        tokens: Int = 0,
        costUsd: Double = 0,
        activeTimeMs: Double = 0,
        unpricedTokens: Int? = nil,
        perClient: [String: HistoryBucket] = [:],
        perModel: [String: HistoryBucket] = [:]
    ) {
        self.month = month
        self.tokens = tokens
        self.costUsd = costUsd
        self.activeTimeMs = activeTimeMs
        self.unpricedTokens = unpricedTokens
        self.perClient = perClient
        self.perModel = perModel
    }

    /// Months have no message total of their own; the Hub's summary sums the
    /// tools' messages (`mergeHistories`).
    public var messages: Int {
        perClient.values.reduce(0) { $0 + $1.messages }
    }
}

extension HubHistoryMonth: Decodable {
    private enum CodingKeys: String, CodingKey {
        case month, tokens, cost, activeTimeMs, unpricedTokens, perClient, perModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = container.lenientString(.month) else {
            throw DecodingError.dataCorruptedError(forKey: .month, in: container, debugDescription: "missing month key")
        }
        let month = String(raw.prefix(7))
        guard month.count == 7, DayKey.isValid("\(month)-01") else {
            throw DecodingError.dataCorruptedError(forKey: .month, in: container, debugDescription: "invalid month key")
        }
        let tokens = nonNegative(container.lenientInt(.tokens) ?? 0)
        self.init(
            month: month,
            tokens: tokens,
            costUsd: nonNegative(container.lenientDouble(.cost) ?? 0),
            activeTimeMs: nonNegative(container.lenientDouble(.activeTimeMs) ?? 0),
            unpricedTokens: HistoryWire.unpriced(container.lenientDouble(.unpricedTokens), tokens: tokens),
            perClient: HistoryWire.clientBuckets(container, .perClient),
            perModel: HistoryWire.buckets(container, .perModel)
        )
    }
}

/// `summary` of a History payload (all of a device's or the Hub's History,
/// not only the capped daily rows), or one computed by `HistoryMath.summary`.
public struct HistorySummary: Sendable, Hashable {
    public var totalTokens: Int
    /// The known (priced) subtotal in USD.
    public var totalCost: Double
    public var activeDays: Int
    public var currentStreak: Int
    public var longestStreak: Int
    public var peakDayTokens: Int
    /// The model with the most tokens; nil when the wire says "" (no models).
    public var favoriteModel: String?
    public var messages: Int
    public var activeTimeMs: Double
    /// Tokens with no price; nil when there are none.
    public var unpricedTokens: Int?

    public init(
        totalTokens: Int = 0,
        totalCost: Double = 0,
        activeDays: Int = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        peakDayTokens: Int = 0,
        favoriteModel: String? = nil,
        messages: Int = 0,
        activeTimeMs: Double = 0,
        unpricedTokens: Int? = nil
    ) {
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.activeDays = activeDays
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.peakDayTokens = peakDayTokens
        self.favoriteModel = favoriteModel
        self.messages = messages
        self.activeTimeMs = activeTimeMs
        self.unpricedTokens = unpricedTokens
    }

    public static let empty = HistorySummary()
}

extension HistorySummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case totalTokens, totalCost, activeDays, currentStreak, longestStreak, peakDayTokens
        case favoriteModel, messages, activeTimeMs, unpricedTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unpriced = nonNegative(container.lenientInt(.unpricedTokens) ?? 0)
        self.init(
            totalTokens: nonNegative(container.lenientInt(.totalTokens) ?? 0),
            totalCost: nonNegative(container.lenientDouble(.totalCost) ?? 0),
            activeDays: nonNegative(container.lenientInt(.activeDays) ?? 0),
            currentStreak: nonNegative(container.lenientInt(.currentStreak) ?? 0),
            longestStreak: nonNegative(container.lenientInt(.longestStreak) ?? 0),
            peakDayTokens: nonNegative(container.lenientInt(.peakDayTokens) ?? 0),
            favoriteModel: container.lenientString(.favoriteModel),
            messages: nonNegative(container.lenientInt(.messages) ?? 0),
            activeTimeMs: nonNegative(container.lenientDouble(.activeTimeMs) ?? 0),
            unpricedTokens: unpriced > 0 ? unpriced : nil
        )
    }
}

/// `GET /api/history`: the merged History of every device that shares it.
///
/// `daily` is capped at 370 days ending at the Hub's today and omits days
/// without usage; `monthly` and `summary` cover all retained History.
public struct HubHistory: Sendable, Equatable {
    /// Ascending by date.
    public var daily: [HubHistoryDay]
    /// Ascending by month.
    public var monthly: [HubHistoryMonth]
    /// nil when the payload has no `summary` object.
    public var summary: HistorySummary?

    public init(daily: [HubHistoryDay] = [], monthly: [HubHistoryMonth] = [], summary: HistorySummary? = nil) {
        self.daily = daily
        self.monthly = monthly
        self.summary = summary
    }

    public static let empty = HubHistory()

    public var isEmpty: Bool { daily.isEmpty && monthly.isEmpty }

    /// Decodes a History body, mapping failures to `HubClientError.decoding`.
    /// Valid JSON that is not an object decodes as `.empty`, like the
    /// desktop's `coerceHistory`.
    public static func decode(from data: Data) throws -> HubHistory {
        do {
            return try JSONDecoder().decode(HubHistory.self, from: data)
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }
}

extension HubHistory: Decodable {
    private enum CodingKeys: String, CodingKey {
        case daily, monthly, summary
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .empty
            return
        }
        self.init(
            daily: container.lenientArray(.daily, of: HubHistoryDay.self).sorted { $0.date < $1.date },
            monthly: container.lenientArray(.monthly, of: HubHistoryMonth.self).sorted { $0.month < $1.month },
            summary: container.lenientObject(.summary, as: HistorySummary.self)
        )
    }
}

/// The History part of one `GET /api/devices` record, for the scoped-device
/// views (Activity, trends, stat cards, fixed ranges) — the desktop's
/// `parseDeviceHistories` (`src/electron/historySource.js`).
public struct DeviceHistoryRecord: Sendable, Equatable, Identifiable {
    /// `deviceId` (else `id`), the key `DeviceSummary.id` uses.
    public var id: String
    /// The producer shares History and the record carries it. False also for
    /// a record whose History is null (disabled) or missing, which fixed
    /// ranges must report as unavailable rather than as zero usage.
    public var historyAvailable: Bool
    /// The device's own History; nil unless `historyAvailable`. Its
    /// `summary` covers all of the device's History, not only `daily`.
    public var history: HubHistory?
    /// `periodWindows.today.key`: the device-local day its `today` is for.
    public var todayWindowKey: String?
    /// `periodWindows.today.endsAt`: the device's next local midnight.
    public var todayEndsAt: Date?
    /// `periodWindows.timeZone`, an IANA identifier as the device sent it.
    public var timeZone: String?
    /// The record's raw `periods.today`, with no expiry applied.
    public var today: UsagePeriod?

    public init(
        id: String,
        historyAvailable: Bool = false,
        history: HubHistory? = nil,
        todayWindowKey: String? = nil,
        todayEndsAt: Date? = nil,
        timeZone: String? = nil,
        today: UsagePeriod? = nil
    ) {
        self.id = id
        self.historyAvailable = historyAvailable
        self.history = history
        self.todayWindowKey = todayWindowKey
        self.todayEndsAt = todayEndsAt
        self.timeZone = timeZone
        self.today = today
    }

    /// Decodes a `GET /api/devices` body (`{devices: [...]}`, or a bare array
    /// as the desktop also accepts). Records without an id or that are not
    /// objects are dropped; a body without a device list is `[]`.
    /// - Throws: `HubClientError.decoding` when the body is not JSON.
    public static func decodeList(from devicesResponse: Data) throws -> [DeviceHistoryRecord] {
        do {
            return try JSONDecoder().decode(DeviceHistoryList.self, from: devicesResponse).records
        } catch {
            throw HubClientError.decoding(String(describing: error))
        }
    }
}

extension DeviceHistoryRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case deviceId, id, historyAvailable, history, periodWindows, periods, today
    }

    private enum WindowKeys: String, CodingKey {
        case today, timeZone
    }

    private enum WindowFieldKeys: String, CodingKey {
        case key, endsAt
    }

    private enum PeriodKeys: String, CodingKey {
        case today
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.deviceId) ?? container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .deviceId, in: container, debugDescription: "record without a device id")
        }
        // `historyAvailable === true && 'history' in record && history !== null`;
        // a History that is not an object reads as empty, like `coerceHistory`.
        let available = container.lenientBool(.historyAvailable) == true && !container.isNullOrMissing(.history)
        let history = available ? (container.lenientObject(.history, as: HubHistory.self) ?? .empty) : nil
        let windows = try? container.nestedContainer(keyedBy: WindowKeys.self, forKey: .periodWindows)
        let todayWindow = try? windows?.nestedContainer(keyedBy: WindowFieldKeys.self, forKey: .today)
        let periods = try? container.nestedContainer(keyedBy: PeriodKeys.self, forKey: .periods)
        self.init(
            id: id,
            historyAvailable: available,
            history: history,
            todayWindowKey: todayWindow?.lenientString(.key).flatMap { DayKey.isValid($0) ? $0 : nil },
            todayEndsAt: todayWindow?.lenientDate(.endsAt),
            timeZone: windows?.lenientString(.timeZone),
            today: periods?.lenientObject(.today, as: UsagePeriod.self)
                ?? container.lenientObject(.today, as: UsagePeriod.self)
        )
    }
}

private struct DeviceHistoryList: Decodable {
    let records: [DeviceHistoryRecord]

    private enum CodingKeys: String, CodingKey {
        case devices
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            records = container.lenientArray(.devices, of: DeviceHistoryRecord.self)
        } else if let rows = try? decoder.singleValueContainer().decode([Lossy<DeviceHistoryRecord>].self) {
            records = rows.compactMap(\.value)
        } else {
            records = []
        }
    }
}

/// Streaks and the Hub summary, ported from `src/shared/history.js`.
public enum HistoryMath {
    /// The Hub's daily cap (`DEFAULT_CAP_DAYS`).
    public static let dailyCapDays = 370

    /// `computeStreaks` over the days with tokens > 0. `currentStreak` counts
    /// back from `todayKey` (0 when today has no usage); `longestStreak` is
    /// the longest run anywhere.
    public static func streaks(daily: [HubHistoryDay], todayKey: String) -> HistoryStreaks {
        streaks(activeDays: Set(daily.lazy.filter { $0.tokens > 0 }.map(\.date)), todayKey: todayKey)
    }

    /// `computeStreaks` for compact rows (preview, snapshot, patched series).
    public static func streaks(daily: [HistoryDay], todayKey: String) -> HistoryStreaks {
        streaks(activeDays: Set(daily.lazy.filter { $0.tokens > 0 }.map(\.date)), todayKey: todayKey)
    }

    /// `computeStreaks` for a set of active `yyyy-MM-dd` keys.
    public static func streaks(activeDays: Set<String>, todayKey: String) -> HistoryStreaks {
        var current = 0
        var cursor: String? = String(todayKey.prefix(10))
        while let key = cursor, activeDays.contains(key) {
            current += 1
            cursor = DayKey.adding(days: -1, to: key)
        }
        var longest = 0
        var run = 0
        var previous: String?
        for key in activeDays.sorted() {
            run = previous.flatMap { DayKey.adding(days: 1, to: $0) } == key ? run + 1 : 1
            longest = max(longest, run)
            previous = key
        }
        return HistoryStreaks(currentStreak: current, longestStreak: longest)
    }

    /// `rollingDailyWindow`: the rows from `capDays - 1` days before
    /// `todayKey` through `todayKey`, in their given order.
    public static func rollingWindow(_ daily: [HubHistoryDay], todayKey: String, capDays: Int = dailyCapDays) -> [HubHistoryDay] {
        guard capDays > 0, let today = DayKey.normalized(todayKey),
              let start = DayKey.adding(days: -(capDays - 1), to: today) else { return [] }
        return daily.filter { $0.date >= start && $0.date <= today }
    }

    /// `favoriteModelOf`: the model with the most tokens over `daily`, nil
    /// when no row has models. On a tie the desktop keeps the model it saw
    /// first in wire order, which decoding does not preserve; the Kit keeps
    /// the one that appears on the earliest day, then the smaller id.
    public static func favoriteModel(daily: [HubHistoryDay]) -> String? {
        var totals: [String: Int] = [:]
        var firstSeen: [String: String] = [:]
        for day in daily {
            for (model, bucket) in day.perModel {
                totals[model, default: 0] += bucket.tokens
                if firstSeen[model] == nil { firstSeen[model] = day.date }
            }
        }
        return totals.min { left, right in
            if left.value != right.value { return left.value > right.value }
            let leftDay = firstSeen[left.key] ?? ""
            let rightDay = firstSeen[right.key] ?? ""
            if leftDay != rightDay { return leftDay < rightDay }
            return left.key < right.key
        }?.key
    }

    /// The summary `mergeHistories` builds (history.js 519-538), which is the
    /// one `GET /api/history` returns: lifetime totals, unpriced tokens,
    /// messages and active time from `monthly` (active time from `daily` when
    /// there are no months); active days, peak, streaks and favourite model
    /// from `daily` within the `capDays` window ending at `todayKey`.
    ///
    /// A device record's own `summary` comes from its uncapped History
    /// instead (`normalizeHistory`), so recomputing it from the record's
    /// capped rows can count fewer active days.
    public static func summary(
        daily: [HubHistoryDay],
        monthly: [HubHistoryMonth],
        todayKey: String,
        capDays: Int = dailyCapDays
    ) -> HistorySummary {
        let window = rollingWindow(daily, todayKey: todayKey, capDays: capDays)
        let streaks = streaks(daily: window, todayKey: todayKey)
        let unpriced = monthly.reduce(0) { $0 + ($1.unpricedTokens ?? 0) }
        let activeTime = monthly.isEmpty
            ? window.reduce(0) { $0 + $1.activeTimeMs }
            : monthly.reduce(0) { $0 + $1.activeTimeMs }
        return HistorySummary(
            totalTokens: monthly.reduce(0) { $0 + $1.tokens },
            totalCost: monthly.reduce(0) { $0 + $1.costUsd },
            activeDays: window.reduce(0) { $0 + ($1.tokens > 0 ? 1 : 0) },
            currentStreak: streaks.currentStreak,
            longestStreak: streaks.longestStreak,
            peakDayTokens: window.reduce(0) { max($0, $1.tokens) },
            favoriteModel: favoriteModel(daily: window),
            messages: monthly.reduce(0) { $0 + $1.messages },
            activeTimeMs: activeTime,
            unpricedTokens: unpriced > 0 ? unpriced : nil
        )
    }
}

/// `computeStreaks`' result.
public struct HistoryStreaks: Sendable, Hashable {
    public var currentStreak: Int
    public var longestStreak: Int

    public init(currentStreak: Int, longestStreak: Int) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }
}

extension HubClient {
    /// `GET /api/history`, decoded. A Hub that predates the endpoint throws
    /// `HubClientError.http(status: 404)`; fall back to the stats preview.
    public func history() async throws -> HubHistory {
        try HubHistory.decode(from: try await historyData())
    }

    /// The raw `GET /api/history` body, for callers that cache it themselves.
    public func historyData() async throws -> Data {
        try await data(for: .history)
    }

    /// The History part of every `GET /api/devices` record.
    public func deviceHistoryRecords() async throws -> [DeviceHistoryRecord] {
        try DeviceHistoryRecord.decodeList(from: try await data(for: .devices))
    }
}

/// Wire normalization shared by the History models.
enum HistoryWire {
    /// The desktop renderers fold only this Tokscale alias (`usageCharts.js`
    /// `CLIENT_ALIASES`, `dashboard.js`, `fixedPeriodRanges.js`): device
    /// records keep the raw key, and every chart must agree with the
    /// breakdown under it about the same day.
    static let clientAliases = ["antigravity-cli": "antigravity"]

    static func canonicalClient(_ key: String) -> String {
        clientAliases[key] ?? key
    }

    /// A value > 0, else nil (absent and 0 read the same on the desktop).
    static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// `unpricedTokensFor`: `min(max(0, tokens), max(0, round(unpriced)))`,
    /// nil when that is 0.
    static func unpriced(_ value: Double?, tokens: Int) -> Int? {
        guard let value else { return nil }
        let count = min(max(0, tokens), max(0, clampedInt(JSCompat.round(value))))
        return count > 0 ? count : nil
    }

    static func buckets<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [String: HistoryBucket] {
        guard !container.isNullOrMissing(key),
              let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return [:] }
        var result: [String: HistoryBucket] = [:]
        for entry in nested.allKeys {
            guard !entry.stringValue.isEmpty, let bucket = nested.lenientObject(entry, as: HistoryBucket.self) else { continue }
            result[entry.stringValue] = bucket
        }
        return result
    }

    /// `foldClientMap`: buckets keyed by canonical client id.
    static func clientBuckets<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [String: HistoryBucket] {
        var result: [String: HistoryBucket] = [:]
        for (raw, bucket) in buckets(container, key) {
            let client = canonicalClient(raw)
            if var existing = result[client] {
                existing.add(bucket)
                result[client] = existing
            } else {
                result[client] = bucket
            }
        }
        return result
    }
}
