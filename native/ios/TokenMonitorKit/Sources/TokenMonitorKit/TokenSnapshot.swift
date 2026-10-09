import Foundation

/// A compact, privacy-safe projection of `HubStats` for widgets,
/// complications and the watch (App Group file, WatchConnectivity payloads).
///
/// Bounded by construction — at most `maxShares` tools/models per period, a
/// `maxTrendDays` trend, primary limit windows only, emails masked — so it
/// stays a few KB however large the Hub's response is.
public struct TokenSnapshot: Sendable, Equatable {
    /// Bump when a field changes meaning; readers ignore newer versions.
    public static let currentSchemaVersion = 1
    public static let maxShares = 6
    public static let maxTrendDays = 30
    public static let maxWindowsPerProvider = 4

    public var schemaVersion: Int
    /// When this device fetched the stats (the age of the cache).
    public var fetchedAt: Date
    /// `HubConnection.snapshotKey` of the Hub the stats came from; nil in
    /// snapshots written before it was recorded (origin unknown).
    public var hubKey: String?
    /// The newest time the Hub heard from any device (the age of the data).
    public var sourceUpdatedAt: Date?
    /// Every device was stale when fetched.
    public var isSourceStale: Bool
    public var today: PeriodSummary
    public var month: PeriodSummary
    public var allTime: PeriodSummary
    /// `LimitProvider.sortedForDisplay`, each `compacted()`.
    public var limits: [LimitProvider]
    public var devices: DeviceCounts
    /// Daily tokens/cost, oldest first, ending on the fetch day.
    public var trend: [HistoryDay]

    public init(
        schemaVersion: Int = TokenSnapshot.currentSchemaVersion,
        fetchedAt: Date,
        hubKey: String? = nil,
        sourceUpdatedAt: Date? = nil,
        isSourceStale: Bool = false,
        today: PeriodSummary,
        month: PeriodSummary,
        allTime: PeriodSummary,
        limits: [LimitProvider] = [],
        devices: DeviceCounts = DeviceCounts(online: 0, total: 0),
        trend: [HistoryDay] = []
    ) {
        self.schemaVersion = schemaVersion
        self.fetchedAt = fetchedAt
        self.hubKey = hubKey
        self.sourceUpdatedAt = sourceUpdatedAt
        self.isSourceStale = isSourceStale
        self.today = today
        self.month = month
        self.allTime = allTime
        self.limits = limits
        self.devices = devices
        self.trend = trend
    }

    /// Projects fresh stats.
    /// - Parameters:
    ///   - hub: the connection the stats were read from, recorded as `hubKey`
    ///     (never the secret). Pass it wherever the Hub is known.
    ///   - trendDays: days of daily trend to keep (clamped to `maxTrendDays`).
    ///   - calendar: the calendar whose "today" ends the trend.
    public init(
        stats: HubStats,
        fetchedAt: Date = Date(),
        hub: HubConnection? = nil,
        trendDays: Int = TokenSnapshot.maxTrendDays,
        calendar: Calendar = .current
    ) {
        self.init(
            fetchedAt: fetchedAt,
            hubKey: hub?.snapshotKey,
            sourceUpdatedAt: stats.newestDeviceActivity,
            isSourceStale: stats.isSourceStale,
            today: PeriodSummary(kind: .today, period: stats.today),
            month: PeriodSummary(kind: .month, period: stats.month),
            allTime: PeriodSummary(kind: .allTime, period: stats.allTime),
            limits: LimitProvider.sortedForDisplay(stats.limits).map { $0.compacted(maxWindows: Self.maxWindowsPerProvider) },
            devices: DeviceCounts(online: stats.onlineDeviceCount, total: stats.devices.count),
            trend: stats.dailyTrend(days: min(max(0, trendDays), Self.maxTrendDays), endingAt: fetchedAt, calendar: calendar)
        )
    }

    public subscript(period: UsagePeriodKind) -> PeriodSummary {
        switch period {
        case .today: return today
        case .month: return month
        case .allTime: return allTime
        }
    }

    /// The snapshot is older than `interval` at `date` — time to show it as
    /// stale and try a refresh.
    public func isOlder(than interval: TimeInterval, at date: Date = Date()) -> Bool {
        date.timeIntervalSince(fetchedAt) > interval
    }

    /// Whether this snapshot may be shown for `connection`: false without a
    /// connection, true when the snapshot predates `hubKey` (origin unknown),
    /// otherwise whether it came from that Hub. A cache, an in-flight fetch or
    /// a pushed snapshot from the previous Hub fails this after a Hub switch.
    public func belongs(to connection: HubConnection?) -> Bool {
        belongs(toHubKey: connection?.snapshotKey)
    }

    /// `belongs(to:)` by `HubConnection.snapshotKey`, for callers that have
    /// only the saved URL (`HubConnectionStore.snapshotKey`).
    public func belongs(toHubKey key: String?) -> Bool {
        guard let key else { return false }
        guard let hubKey else { return true }
        return hubKey == key
    }

    /// Whether `period`'s figures still describe that period at `date`: a
    /// snapshot fetched on an earlier day (month) holds that day's (month's)
    /// "today" ("this month"), so after midnight its totals must not be shown
    /// as today's. Days and months are `calendar`'s — the device's, as on
    /// every other date the widgets and complications draw. All time is
    /// always current.
    public func isCurrent(_ period: UsagePeriodKind, at date: Date, calendar: Calendar = .current) -> Bool {
        switch period {
        case .today: return calendar.isDate(fetchedAt, inSameDayAs: date)
        case .month: return calendar.isDate(fetchedAt, equalTo: date, toGranularity: .month)
        case .allTime: return true
        }
    }

    /// Compact JSON (no whitespace) — the form `SnapshotStore` writes and the
    /// watch bridge should send.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(TokenSnapshot.self, from: jsonData)
    }
}

extension TokenSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, fetchedAt, hubKey, sourceUpdatedAt, isSourceStale, today, month, allTime, limits, devices, trend
    }

    // Dates are written as ISO 8601 strings by hand, so any encoder/decoder
    // pair round-trips them (the default strategies disagree across platforms).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let fetchedAt = container.lenientDate(.fetchedAt) else {
            throw DecodingError.dataCorruptedError(forKey: .fetchedAt, in: container, debugDescription: "snapshot without fetchedAt")
        }
        self.init(
            schemaVersion: container.lenientInt(.schemaVersion) ?? 0,
            fetchedAt: fetchedAt,
            hubKey: container.lenientString(.hubKey),
            sourceUpdatedAt: container.lenientDate(.sourceUpdatedAt),
            isSourceStale: container.lenientBool(.isSourceStale) ?? false,
            today: container.lenientObject(.today, as: PeriodSummary.self) ?? PeriodSummary(kind: .today),
            month: container.lenientObject(.month, as: PeriodSummary.self) ?? PeriodSummary(kind: .month),
            allTime: container.lenientObject(.allTime, as: PeriodSummary.self) ?? PeriodSummary(kind: .allTime),
            limits: container.lenientArray(.limits, of: LimitProvider.self),
            devices: container.lenientObject(.devices, as: DeviceCounts.self) ?? DeviceCounts(online: 0, total: 0),
            trend: container.lenientArray(.trend, of: HistoryDay.self)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeISODate(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(hubKey, forKey: .hubKey)
        try container.encodeISODate(sourceUpdatedAt, forKey: .sourceUpdatedAt)
        if isSourceStale { try container.encode(true, forKey: .isSourceStale) }
        try container.encode(today, forKey: .today)
        try container.encode(month, forKey: .month)
        try container.encode(allTime, forKey: .allTime)
        try container.encode(limits, forKey: .limits)
        try container.encode(devices, forKey: .devices)
        try container.encode(trend, forKey: .trend)
    }
}

/// One period, reduced to what compact surfaces show.
public struct PeriodSummary: Sendable, Equatable, Codable {
    public var kind: UsagePeriodKind
    public var totalTokens: Int
    public var costUsd: Double
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var unclassifiedTokens: Int
    public var outputTokensPerSecond: Double?
    /// Top tools (compact labels: "Claude", not "Claude Code"), tokens descending.
    public var tools: [UsageShare]
    /// Top models, tokens descending.
    public var models: [UsageShare]
    /// Tokens of the period not in `tools` (rows beyond the top ones plus
    /// unattributed usage) — draw it as a neutral "Other" segment.
    public var otherToolTokens: Int
    /// Tokens of the period not in `models`.
    public var otherModelTokens: Int

    public init(
        kind: UsagePeriodKind,
        totalTokens: Int = 0,
        costUsd: Double = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        unclassifiedTokens: Int = 0,
        outputTokensPerSecond: Double? = nil,
        tools: [UsageShare] = [],
        models: [UsageShare] = [],
        otherToolTokens: Int = 0,
        otherModelTokens: Int = 0
    ) {
        self.kind = kind
        self.totalTokens = totalTokens
        self.costUsd = costUsd
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.unclassifiedTokens = unclassifiedTokens
        self.outputTokensPerSecond = outputTokensPerSecond
        self.tools = tools
        self.models = models
        self.otherToolTokens = otherToolTokens
        self.otherModelTokens = otherModelTokens
    }

    public init(kind: UsagePeriodKind, period: UsagePeriod, maxShares: Int = TokenSnapshot.maxShares) {
        let limit = max(0, maxShares)
        let tools = period.clients.prefix(limit).map { share in
            UsageShare(kind: .client, id: share.id, label: VendorCatalog.toolLabel(share.id), tokens: share.tokens, costUsd: share.costUsd, vendorID: share.vendorID)
        }
        let models = Array(period.models.prefix(limit))
        self.init(
            kind: kind,
            totalTokens: period.totalTokens,
            costUsd: period.costUsd,
            outputTokens: period.outputTokens,
            cacheReadTokens: period.cacheReadTokens,
            cacheWriteTokens: period.cacheWriteTokens,
            unclassifiedTokens: period.unclassifiedTokens,
            outputTokensPerSecond: period.outputTokensPerSecond,
            tools: tools,
            models: models,
            otherToolTokens: max(0, period.totalTokens - tools.reduce(0) { $0 + $1.tokens }),
            otherModelTokens: max(0, period.totalTokens - models.reduce(0) { $0 + $1.tokens })
        )
    }

    public var components: TokenComponents {
        TokenComponents(
            totalTokens: totalTokens,
            cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens,
            unclassifiedTokens: unclassifiedTokens
        )
    }

    /// Tools plus an "Other" remainder row named by the caller.
    public func tools(otherLabel label: String) -> [UsageShare] {
        otherToolTokens > 0 ? tools + [UsageShare.remainder(label: label, tokens: otherToolTokens)] : tools
    }

    /// Models plus an "Other" remainder row named by the caller.
    public func models(otherLabel label: String) -> [UsageShare] {
        otherModelTokens > 0 ? models + [UsageShare.remainder(label: label, tokens: otherModelTokens)] : models
    }
}

public struct DeviceCounts: Sendable, Equatable, Codable {
    public var online: Int
    public var total: Int

    public init(online: Int, total: Int) {
        self.online = online
        self.total = total
    }

    public var stale: Int { max(0, total - online) }
}

/// The App Group file the iOS app, its widgets, the watch app and its
/// complications share. The only snapshot location: do not invent another.
public struct SnapshotStore: Sendable {
    public static let fileName = "token-snapshot.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container's store, nil without the entitlement.
    public static var appGroup: SnapshotStore? {
        AppGroup.containerURL.map { SnapshotStore(directory: $0.appendingPathComponent("Library/Caches/TokenMonitor", isDirectory: true)) }
    }

    /// `appGroup`, else the app's own caches directory (the app keeps working
    /// in a build without the App Group; its widgets simply see no data).
    public static var shared: SnapshotStore {
        if let store = appGroup { return store }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return SnapshotStore(directory: caches.appendingPathComponent("TokenMonitor", isDirectory: true))
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// The stored snapshot; nil when there is none, it is unreadable, or it
    /// was written by a newer schema.
    public func load() -> TokenSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? TokenSnapshot(jsonData: data),
              snapshot.schemaVersion <= TokenSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    /// Writes atomically, so a widget reading concurrently sees the old or the
    /// new file, never half of one.
    public func save(_ snapshot: TokenSnapshot) throws {
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
