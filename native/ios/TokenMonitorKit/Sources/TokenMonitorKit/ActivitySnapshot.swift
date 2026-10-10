import Foundation

/// The compact daily activity the app writes to the App Group for the
/// Activity widget, which never decodes `/api/history` itself (the macOS
/// widget gets its history from the desktop app the same way).
///
/// One entry per calendar day from `startDay` through the day it was
/// generated (at most `maxDays`), zero-filled and already patched with live
/// today. The range covers the whole rolling-year grid (from the Sunday on or
/// before its first day) and, within `maxDays`, every History day the app
/// had, so the widget's intensity scale matches the app's
/// (`HeatmapBuilder.maximum` reads every supplied day).
public struct ActivitySnapshot: Sendable, Equatable {
    /// The format version this build writes.
    public static let currentSchemaVersion = 1
    /// The widget kind that draws this snapshot; never rename it (a renamed
    /// kind silently drops every widget the user placed).
    public static let widgetKind = "TokenMonitorActivityWidget"
    /// A rolling year's grid needs at most 372 days (12 months back to a 1st,
    /// then back to a Sunday); the History cap is 370.
    public static let maxDays = 372
    /// The encoded size budget (`jsonData()`).
    public static let maxEncodedBytes = 12 * 1024

    public var schemaVersion: Int
    /// `HubConnection.snapshotKey` of the Hub it came from.
    public var hubKey: String?
    /// The scoped device, nil for all devices.
    public var scopeDeviceID: String?
    public var generatedAt: Date
    /// `yyyy-MM-dd` of `tokens[0]` / `costMicros[0]`.
    public var startDay: String
    public var tokens: [Int]
    /// USD × 1_000_000, rounded.
    public var costMicros: [Int]
    /// The History summary's active days (all retained History), for the
    /// "All time" active-days chip; nil when the app had no summary.
    public var summaryActiveDays: Int?
    /// The History summary's peak day, for the long-range "Peak" figure;
    /// nil when the app had no summary.
    public var summaryPeakDayTokens: Int?

    public init(
        schemaVersion: Int = ActivitySnapshot.currentSchemaVersion,
        hubKey: String?,
        scopeDeviceID: String?,
        generatedAt: Date,
        startDay: String,
        tokens: [Int],
        costMicros: [Int],
        summaryActiveDays: Int? = nil,
        summaryPeakDayTokens: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.hubKey = hubKey
        self.scopeDeviceID = scopeDeviceID
        self.generatedAt = generatedAt
        self.startDay = startDay
        self.tokens = tokens
        self.costMicros = costMicros
        self.summaryActiveDays = summaryActiveDays
        self.summaryPeakDayTokens = summaryPeakDayTokens
    }

    /// The snapshot of `daily` (already patched with live today, see
    /// `HistorySeries.dailyWithLiveToday`) ending on `generatedAt`'s day in
    /// `calendar` — the day key the app patched today into. `summary` (the
    /// History's own) feeds the "All time" active days and the long-range
    /// peak.
    public init(
        daily: [HistoryDay],
        hubKey: String?,
        scopeDeviceID: String?,
        generatedAt: Date,
        calendar: Calendar = .current,
        summary: HistorySummary? = nil
    ) {
        self.init(
            daily: daily,
            todayKey: DayKey.string(from: generatedAt, calendar: calendar),
            hubKey: hubKey,
            scopeDeviceID: scopeDeviceID,
            generatedAt: generatedAt,
            summary: summary
        )
    }

    /// The snapshot of `daily` (already patched with live today) ending on
    /// `todayKey` — for a scoped device, its own day
    /// (`FixedRanges.deviceDayState`). Rows after `todayKey` are dropped.
    /// `summary` (the History's own) feeds the "All time" active days and the
    /// long-range peak.
    public init(
        daily: [HistoryDay],
        todayKey: String,
        hubKey: String?,
        scopeDeviceID: String?,
        generatedAt: Date,
        summary: HistorySummary? = nil
    ) {
        let end = CivilDay.normalized(todayKey) ?? DayKey.string(from: generatedAt, calendar: DayKey.utcCalendar)
        let endNumber = CivilDay.number(end) ?? 0
        let gridStart = HeatmapBuilder.rollingYearStart(todayKey: end).flatMap(CivilDay.number) ?? endNumber
        let gridFirst = gridStart - CivilDay.weekday(gridStart)
        var values: [Int: (tokens: Int, micros: Int)] = [:]
        var earliest = gridFirst
        for day in daily {
            guard let key = CivilDay.normalized(day.date), let number = CivilDay.number(key), number <= endNumber else { continue }
            values[number] = (max(0, day.tokens), max(0, clampedInt(day.costUsd * 1_000_000)))
            earliest = min(earliest, number)
        }
        let first = max(endNumber - (Self.maxDays - 1), earliest)
        var tokens: [Int] = []
        var micros: [Int] = []
        tokens.reserveCapacity(endNumber - first + 1)
        micros.reserveCapacity(endNumber - first + 1)
        if first <= endNumber {
            for number in first...endNumber {
                let value = values[number]
                tokens.append(value?.tokens ?? 0)
                micros.append(value?.micros ?? 0)
            }
        }
        self.init(
            hubKey: hubKey,
            scopeDeviceID: scopeDeviceID,
            generatedAt: generatedAt,
            startDay: CivilDay.key(first),
            tokens: tokens,
            costMicros: micros,
            summaryActiveDays: summary?.activeDays,
            summaryPeakDayTokens: summary?.peakDayTokens
        )
    }

    /// The last day the snapshot holds (`yyyy-MM-dd`), nil when it is empty.
    public var endDay: String? {
        guard !tokens.isEmpty else { return nil }
        return CivilDay.adding(tokens.count - 1, to: startDay)
    }

    /// The snapshot as compact days, oldest first.
    public var days: [HistoryDay] {
        guard let start = CivilDay.number(startDay) else { return [] }
        return tokens.indices.map { index in
            HistoryDay(date: CivilDay.key(start + index), tokens: tokens[index], costUsd: cost(at: index))
        }
    }

    /// The Activity mosaic ending on the day `today` falls on in `calendar`,
    /// or on the snapshot's last day when that is later (a scoped device
    /// whose own day is ahead of the phone's) — the app's builder, so levels,
    /// columns and month labels match it. Days after the snapshot's last day
    /// (a snapshot from an earlier day) read as empty.
    public func heatmap(metric: HeatmapMetric, today: Date, calendar: Calendar = .current) -> HeatmapModel {
        let key = DayKey.string(from: today, calendar: calendar)
        return heatmap(metric: metric, todayKey: max(key, endDay ?? key))
    }

    /// The Activity mosaic ending on `todayKey`.
    public func heatmap(metric: HeatmapMetric, todayKey: String) -> HeatmapModel {
        HeatmapBuilder.rollingYear(days: days.map(HeatmapDay.init), metric: metric, todayKey: todayKey)
    }

    /// The active-days chip (`ActiveDays.count`): the grid's active cells for
    /// "Last 12 months", else the History summary's figure when the app had
    /// one.
    public func activeDays(window: ActiveDaysWindow, grid: HeatmapGrid) -> Int {
        switch window {
        case .year: return grid.activeDayCount
        case .all: return summaryActiveDays ?? grid.activeDayCount
        }
    }

    /// The long-range peak day (`longRangePeakDayTokens`): the larger of the
    /// History summary's peak and the busiest day held here.
    public var peakDayTokens: Int {
        max(0, summaryPeakDayTokens ?? 0, tokens.max() ?? 0)
    }

    /// Whether this snapshot may be shown for the Hub `key` and `scope`:
    /// false without a Hub, true for the Hub when the snapshot predates
    /// `hubKey` (as `TokenSnapshot.belongs(toHubKey:)`), and the scoped
    /// device must match.
    public func belongs(toHubKey key: String?, scope: DeviceScope) -> Bool {
        guard let key else { return false }
        if let hubKey, hubKey != key { return false }
        return scopeDeviceID == scope.deviceID
    }

    /// `belongs(toHubKey:scope:)` for a connection.
    public func belongs(to connection: HubConnection?, scope: DeviceScope) -> Bool {
        belongs(toHubKey: connection?.snapshotKey, scope: scope)
    }

    /// The snapshot is older than `interval` at `date` (the widget's stale
    /// indicator uses a day).
    public func isOlder(than interval: TimeInterval, at date: Date = Date()) -> Bool {
        date.timeIntervalSince(generatedAt) > interval
    }

    /// Compact JSON with sorted keys — the form `ActivitySnapshotStore`
    /// writes (budget: `maxEncodedBytes`).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(ActivitySnapshot.self, from: jsonData)
    }

    private func cost(at index: Int) -> Double {
        guard costMicros.indices.contains(index) else { return 0 }
        return Double(costMicros[index]) / 1_000_000
    }
}

extension ActivitySnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hubKey, scopeDeviceID, generatedAt, startDay, tokens, costMicros
        case summaryActiveDays, summaryPeakDayTokens
    }

    // Dates are written as ISO 8601 strings by hand, so any encoder/decoder
    // pair round-trips them (like `TokenSnapshot`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let generatedAt = container.lenientDate(.generatedAt) else {
            throw DecodingError.dataCorruptedError(forKey: .generatedAt, in: container, debugDescription: "activity without generatedAt")
        }
        guard let startDay = container.lenientString(.startDay).flatMap(CivilDay.normalized) else {
            throw DecodingError.dataCorruptedError(forKey: .startDay, in: container, debugDescription: "activity without a start day")
        }
        let tokens = Self.counts(container, .tokens)
        var micros = Self.counts(container, .costMicros)
        if micros.count < tokens.count {
            micros += Array(repeating: 0, count: tokens.count - micros.count)
        } else if micros.count > tokens.count {
            micros = Array(micros.prefix(tokens.count))
        }
        self.init(
            schemaVersion: container.lenientInt(.schemaVersion) ?? 0,
            hubKey: container.lenientString(.hubKey),
            scopeDeviceID: container.lenientString(.scopeDeviceID),
            generatedAt: generatedAt,
            startDay: startDay,
            tokens: tokens,
            costMicros: micros,
            summaryActiveDays: container.lenientInt(.summaryActiveDays).map(nonNegative),
            summaryPeakDayTokens: container.lenientInt(.summaryPeakDayTokens).map(nonNegative)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(hubKey, forKey: .hubKey)
        try container.encodeIfPresent(scopeDeviceID, forKey: .scopeDeviceID)
        try container.encodeISODate(generatedAt, forKey: .generatedAt)
        try container.encode(startDay, forKey: .startDay)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(costMicros, forKey: .costMicros)
        try container.encodeIfPresent(summaryActiveDays, forKey: .summaryActiveDays)
        try container.encodeIfPresent(summaryPeakDayTokens, forKey: .summaryPeakDayTokens)
    }

    /// A number array; anything else (or a non-number element) reads as 0.
    private static func counts(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Int] {
        guard let values = try? container.decode([Double?].self, forKey: key) else { return [] }
        return values.map { nonNegative(clampedInt($0 ?? 0)) }
    }
}

/// The App Group file the app writes and the Activity widget reads
/// (`activity.json`, next to `token-snapshot.json`).
public struct ActivitySnapshotStore: Sendable {
    public static let fileName = "activity.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container's store, nil without the entitlement.
    public static var appGroup: ActivitySnapshotStore? {
        SnapshotStore.appGroup.map { ActivitySnapshotStore(directory: $0.directory) }
    }

    /// `appGroup`, else the app's own caches directory (as `SnapshotStore`).
    public static var shared: ActivitySnapshotStore {
        ActivitySnapshotStore(directory: SnapshotStore.shared.directory)
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// The stored snapshot; nil when there is none, it is unreadable, or it
    /// was written by a newer schema.
    public func load() -> ActivitySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? ActivitySnapshot(jsonData: data),
              snapshot.schemaVersion <= ActivitySnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    /// The stored snapshot when it belongs to the Hub `hubKey` and `scope`
    /// (`ActivitySnapshot.belongs(toHubKey:scope:)`), else nil.
    public func load(hubKey: String?, scope: DeviceScope) -> ActivitySnapshot? {
        guard let snapshot = load(), snapshot.belongs(toHubKey: hubKey, scope: scope) else { return nil }
        return snapshot
    }

    /// Writes atomically, so a widget reading concurrently sees the old or the
    /// new file, never half of one.
    public func save(_ snapshot: ActivitySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(watchOS)
        // Readable by widgets while the device is locked, after first unlock.
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try snapshot.jsonData().write(to: fileURL, options: options)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
