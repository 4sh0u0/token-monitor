import Foundation
import Observation
import TokenMonitorKit
import WidgetKit

/// The History behind the Activity mosaic, Trends, the stat cards and the
/// fixed ranges WEEK / 7D / 30D, for the current device scope.
///
/// - All devices read `GET /api/history`; a scoped device reads its record
///   from `GET /api/devices`, as the desktop's fixed ranges do (a device's
///   History is not in `/api/stats`). Records are also loaded on demand for
///   the device screens (`ensureDeviceRecordsLoaded()`).
/// - Nothing is fetched until a view asks (`ensureLoaded()`). After that each
///   stats update refetches only when the Hub's `historyRevision` (all
///   devices) or `deviceHistoryRevision` (records) moves, or the scope needs
///   a source not loaded yet; a Hub without revisions is keyed by its whole
///   History preview, like the desktop's `homeHistorySignature`.
/// - A failed or raced-empty load is retried 3× at 4 s for the same
///   revision; the last good History stays on screen meanwhile.
/// - A Hub without `/api/history` (404/405) falls back to the stats' History
///   preview (`isPreviewFallback`) and is not asked again until the
///   connection changes. The preview also stands in while a first load has
///   failed.
/// - Model aliases are applied with `ModelAliasResolver.forHistory` over the
///   loaded History and records (the desktop's `projectModelAliasHistory`);
///   an alias change re-projects without refetching.
/// - Bodies are cached on disk per Hub (`HubResponseCache`), so a relaunch
///   shows the last History at once and refetches only on a new revision.
/// - After every load the current scope's activity is written to the App
///   Group for the Activity widget (`ActivitySnapshot`: the widget never
///   decodes History itself), and again as live today moves (at most once
///   a minute). The widget kind is reloaded at most every 5 minutes, except
///   right after a scope or Hub change.
@MainActor
@Observable
final class HistoryStore {
    enum Phase: Equatable, Sendable {
        /// Not requested yet (no view has called `ensureLoaded()`), or no Hub.
        case idle
        /// The scope's first load is in flight and nothing is held for it.
        case loading
        /// `history` is the scope's History (or the preview when the Hub has
        /// no `/api/history`), or the scope has none (`isHistoryAvailable`).
        case ready
        /// The load failed and nothing is held for the scope. For all devices
        /// `history` is then the stats preview (`isPreviewFallback`).
        case failed
    }

    // MARK: State views read

    private(set) var phase: Phase = .idle
    /// The current scope's History with model aliases applied: `/api/history`
    /// for all devices, the scoped device's own record, or the stats preview
    /// (`isPreviewFallback`). Live today is not patched in; see `daily`.
    private(set) var history: HubHistory?
    /// `history` is the stats' History preview (latest 30 days, no tool or
    /// model buckets): the Hub has no `/api/history`, or the first load
    /// failed. Charts built from it cannot stack, and fixed ranges are
    /// unavailable.
    private(set) var isPreviewFallback = false
    /// The scope has History. False for a scoped device that does not share
    /// it (or is not in `/api/devices`), and while nothing is loaded.
    private(set) var isHistoryAvailable = false
    /// `history.daily` with the live today patched in
    /// (`HistorySeries.dailyWithLiveToday`, or `deviceDaily` for a device),
    /// ascending. The input of the heatmap, trends and the Home trend.
    private(set) var daily: [HubHistoryDay] = []
    /// The day the scope's views end on: the phone's day, or a scoped
    /// device's own day (`FixedRanges.deviceDayState`).
    private(set) var todayKey: String
    /// The scope `history` is for: the requested one, or `.all` when the
    /// scoped device is not on the Hub any more.
    private(set) var scope: DeviceScope = .all
    /// The scope that was asked for (`DisplayPreferences.deviceScope`).
    private(set) var requestedScope: DeviceScope = .all
    /// The last load failure (kept while older History stays on screen).
    private(set) var lastError: HubClientError?
    /// When the current scope's source was last loaded (or saved to the
    /// disk cache that was read).
    private(set) var loadedAt: Date?
    /// `GET /api/devices` has been loaded for this Hub.
    private(set) var deviceRecordsLoaded = false
    /// No device records are held and none are on their way: the Hub has no
    /// `GET /api/devices`, or the last load failed (a retry may still clear
    /// it).
    private(set) var deviceRecordsUnavailable = false

    /// The History summary of the scope (all retained History, not only
    /// `daily`).
    var summary: HistorySummary? { history?.summary }
    var isLoading: Bool { phase == .loading }
    /// Trends can stack by tool or model (not from the preview).
    var canStack: Bool { history != nil && !isPreviewFallback }

    // MARK: Tuning

    /// `HOME_HISTORY_MAX_RETRIES` / `FIXED_PERIOD_HISTORY_MAX_RETRIES`.
    static let maxRetries = 3
    /// `HOME_HISTORY_RETRY_MS` / `FIXED_PERIOD_HISTORY_RETRY_MS`.
    static let retryDelay: Duration = .seconds(4)
    /// The activity file is rewritten at most this often while live today
    /// moves (a load, a scope or a Hub change writes at once).
    static let activityWriteInterval: TimeInterval = 60
    /// Unchanged activity is rewritten this often so its age stays current.
    static let activityRefreshInterval: TimeInterval = 60 * 60
    /// WidgetKit budgets reloads: the Activity widget is reloaded at most
    /// this often, except right after a scope or Hub change.
    static let activityReloadInterval: TimeInterval = 5 * 60

    // MARK: Private state

    private enum SourceKind { case aggregate, records }

    private enum FetchOutcome<Value: Sendable>: Sendable {
        case success(Value, Data)
        case unsupported
        case failure(HubClientError)
        case cancelled
    }

    /// One Hub source (`/api/history` or `/api/devices`) for the current Hub.
    private struct Source<Value: Sendable> {
        /// The last good body, decoded, without aliases.
        var raw: Value?
        /// Bumped whenever `raw` changes.
        var token = 0
        /// The signature `raw` was fetched for.
        var loadedSignature: String?
        /// Recorded before each fetch; nil until the first attempt.
        var attemptedSignature: String?
        /// A cache read or fetch in flight.
        var task: Task<Void, Never>?
        var retryTask: Task<Void, Never>?
        var retrySignature: String?
        var retries = 0
        /// The last attempt failed (or came back empty while data exists).
        var failed = false
        /// The Hub answered 404/405: not asked again for this connection.
        var unsupported = false
        /// The disk cache was read for this Hub.
        var cacheChecked = false
        var loadedAt: Date?

        mutating func cancelWork() {
            task?.cancel()
            task = nil
            retryTask?.cancel()
            retryTask = nil
        }

        /// Counts a retry for `signature`; false once `limit` are spent.
        mutating func takeRetry(for signature: String, limit: Int) -> Bool {
            if retrySignature != signature {
                retrySignature = signature
                retries = 0
            }
            guard retries < limit else { return false }
            retries += 1
            return true
        }

        mutating func clearRetries() {
            retryTask?.cancel()
            retryTask = nil
            retrySignature = nil
            retries = 0
        }
    }

    private enum AliasInput: Equatable {
        case document(ModelAliasDocument?)
        case resolver(ModelAliasResolver?)
    }

    /// The loaded sources with aliases applied.
    private struct Projection: Sendable {
        var aggregateToken: Int
        var recordsToken: Int
        var aliasVersion: Int
        var aggregate: HubHistory?
        var records: [String: DeviceHistoryRecord]
        var resolver: ModelAliasResolver?
    }

    private struct ProjectionInput: Sendable {
        var aggregate: HubHistory?
        var records: [DeviceHistoryRecord]?
        var document: ModelAliasDocument?
        var resolver: ModelAliasResolver?
        var usesResolver: Bool
    }

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let historyCache: HubResponseCache
    @ObservationIgnored private let devicesCache: HubResponseCache
    @ObservationIgnored private let activityStore: ActivitySnapshotStore?

    @ObservationIgnored private var connection: HubConnection?
    /// Observed: `fixedRange` and the device helpers read the live today
    /// from it, so views calling them follow the stream.
    private var stats: HubStats?
    @ObservationIgnored private var aliasInput: AliasInput = .document(nil)
    @ObservationIgnored private var aliasVersion = 0
    /// A view wants the scope's History.
    @ObservationIgnored private var requested = false
    /// A view wants every device's record (device screens).
    @ObservationIgnored private var recordsRequested = false
    @ObservationIgnored private var aggregate = Source<HubHistory>()
    @ObservationIgnored private var records = Source<[DeviceHistoryRecord]>()
    /// Observed: `deviceRecord`, `fixedRange` and `liveToday` read it.
    private var projection: Projection?
    @ObservationIgnored private var projectionTask: Task<Void, Never>?
    /// Bumped on every reset; work started before it is dropped.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private var lastActivity: ActivitySnapshot?
    @ObservationIgnored private var lastActivityWrite: Date?
    @ObservationIgnored private var lastActivityReload: Date?
    @ObservationIgnored private var forceActivityReload = false
    /// New History was projected (or the preview took over): write the
    /// activity file without the throttle.
    @ObservationIgnored private var activityWriteDue = false
    @ObservationIgnored private var pendingActivity: ActivitySnapshot?
    @ObservationIgnored private var pendingActivityTask: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        historyCache: HubResponseCache = HubResponseCache(name: "history"),
        devicesCache: HubResponseCache = HubResponseCache(name: "devices"),
        activityStore: ActivitySnapshotStore? = .shared
    ) {
        self.session = session
        self.historyCache = historyCache
        self.devicesCache = devicesCache
        self.activityStore = activityStore
        self.todayKey = DayKey.string(from: Date(), calendar: .current)
    }

    // MARK: Inputs

    /// Feeds the latest stats (raw or presented: only the revisions, the
    /// preview, the device list and the live today are read), the scope and
    /// the connection, after every stats update. Refetches only when a
    /// revision or the scope's source changes; a different Hub resets the
    /// store. `resolver` is the shared model-alias document (the History
    /// resolver is built from it over the loaded History).
    func update(stats: HubStats?, scope: DeviceScope, connection: HubConnection?, resolver aliases: ModelAliasDocument?) {
        apply(stats: stats, scope: scope, connection: connection, aliases: .document(aliases))
    }

    /// `update` with a ready alias resolver (for example
    /// `ModelAliasResolver.forStats`), applied to History as is.
    @_disfavoredOverload
    func update(stats: HubStats?, scope: DeviceScope, connection: HubConnection?, resolver: ModelAliasResolver?) {
        apply(stats: stats, scope: scope, connection: connection, aliases: .resolver(resolver))
    }

    /// `update` from the presented stats (`HubStats.presenting(scope:aliases:)`).
    func update(presented: ScopedStats?, connection: HubConnection?, aliases: ModelAliasDocument?) {
        apply(stats: presented?.stats, scope: presented?.scope ?? requestedScope, connection: connection, aliases: .document(aliases))
    }

    /// Asks for the current scope's History. Cheap and idempotent, and safe
    /// to call from a view's `onAppear` / `task`: state changes happen on
    /// the next main-actor turn.
    func ensureLoaded() {
        guard !requested else { return }
        requested = true
        Task { [weak self] in
            guard let self else { return }
            self.recompute()
            self.reconcile()
        }
    }

    /// Asks for every device's History record (`GET /api/devices`) whatever
    /// the scope, for the device screens' fixed ranges and trends.
    func ensureDeviceRecordsLoaded() {
        guard !recordsRequested else { return }
        recordsRequested = true
        Task { [weak self] in
            self?.reconcile()
        }
    }

    /// Refetches the sources in use now (pull to refresh), keeping what is
    /// on screen until the answer arrives. A Hub that lacks `/api/history`
    /// is asked again.
    func refresh() {
        requested = true
        aggregate.unsupported = false
        records.unsupported = false
        aggregate.clearRetries()
        records.clearRetries()
        reconcile(force: true)
    }

    /// Forgets everything (Hub switch or disconnect). `clearingCaches` (the
    /// default) also removes the on-disk bodies and the Activity widget's
    /// file; pass false to keep them.
    func reset(clearingCaches: Bool = true) {
        connection = nil
        stats = nil
        resetState()
        if clearingCaches {
            historyCache.clear()
            devicesCache.clear()
            clearActivity()
        }
    }

    // MARK: Derived values

    /// The device History record (aliases applied), when `/api/devices` is
    /// loaded (`ensureDeviceRecordsLoaded()`, or a device scope).
    func deviceRecord(id: String) -> DeviceHistoryRecord? {
        guard let projection, projection.recordsToken > 0 else { return nil }
        return projection.records[id]
    }

    /// A fixed range (WEEK / 7D / 30D) of the current scope; `.native` for a
    /// Hub period. All devices: `/api/history` plus the live `today`
    /// (`today`, else the latest stats' aggregate today) on the phone's day
    /// (the desktop merges per-device days instead, which differs only for
    /// devices in other time zones). A scoped device: its record on its own
    /// day, with its live today from the stats (`today` is not used).
    /// Unavailable while History is not loaded (check `phase`), on the
    /// preview fallback, and for a device that does not share History.
    func fixedRange(_ selection: PeriodSelection, today: UsagePeriod? = nil, now: Date = Date()) -> FixedRangeSnapshot {
        guard selection.isDerived else { return FixedRangeSnapshot(status: .native, selection: selection) }
        if let deviceID = effectiveScope.deviceID {
            return deviceFixedRange(selection, deviceID: deviceID, now: now)
        }
        let calendar = Calendar.current
        guard let history = projection?.aggregate else {
            return FixedRangeSnapshot(status: .unavailable(.historyUnavailable), selection: selection)
        }
        return FixedRanges.snapshot(
            selection: selection,
            daily: history.daily,
            todayKey: DayKey.string(from: now, calendar: calendar),
            today: liveToday(today ?? stats?.today),
            historyAvailable: true,
            firstWeekday: calendar.firstWeekday
        )
    }

    /// A fixed range of one device (`FixedRanges.deviceSnapshot`) from its
    /// record, whatever the scope; unavailable until the records are loaded
    /// (`ensureDeviceRecordsLoaded()`).
    func deviceFixedRange(_ selection: PeriodSelection, deviceID: String, now: Date = Date()) -> FixedRangeSnapshot {
        guard selection.isDerived else { return FixedRangeSnapshot(status: .native, selection: selection) }
        guard let record = deviceRecord(id: deviceID) else {
            return FixedRangeSnapshot(status: .unavailable(.historyUnavailable), selection: selection)
        }
        let calendar = Calendar.current
        let device = stats?.device(id: deviceID)
        return FixedRanges.deviceSnapshot(
            selection: selection,
            record: record,
            device: device,
            liveToday: liveToday(device?.detail(.today)),
            now: now,
            firstWeekday: calendar.firstWeekday,
            calendar: calendar
        )
    }

    /// One device's History rows with its live today patched in, on its own
    /// day (`HistorySeries.deviceDaily`); nil until the records are loaded or
    /// when the device shares no History.
    func deviceDaily(id: String, now: Date = Date()) -> DeviceHistoryDaily? {
        guard let record = deviceRecord(id: id) else { return nil }
        return HistorySeries.deviceDaily(
            record: record,
            liveToday: liveToday(stats?.device(id: id)?.detail(.today)),
            now: now,
            fallbackTodayKey: DayKey.string(from: now, calendar: .current)
        )
    }

    /// The rolling-year Activity mosaic of the scope (Sunday-first).
    func heatmap(metric: HeatmapMetric) -> HeatmapGrid {
        HeatmapBuilder.rollingYear(daily: daily, metric: metric, todayKey: todayKey)
    }

    /// The Home "Trend": the last `days` calendar days as a token line.
    func homeTrend(days: Int = HistoryInsights.homeTrendDays) -> HomeTrend {
        HistoryInsights.homeTrend(daily: daily, todayKey: todayKey, summary: summary, days: days)
    }

    /// A Trends range: N calendar days ending today (`.all`: from the first
    /// History day), zero-filled, live today patched in.
    func trendDays(_ range: TrendRange) -> [HubHistoryDay] {
        HistorySeries.range(range, daily: daily, todayKey: todayKey)
    }

    /// The summary stat cards (`StatCards.cards`); empty without a summary.
    var statCards: [StatCard] {
        summary.map(StatCards.cards(summary:)) ?? []
    }

    /// The active-days chip for `window` (`ActiveDays.count`).
    func activeDays(window: ActiveDaysWindow, grid: HeatmapGrid) -> Int {
        ActiveDays.count(window: window, summary: summary, grid: grid)
    }

    /// `activityStatsForPeriod` for the Overview hero and Activity module.
    func activityStats(selection: PeriodSelection, fixedRange: FixedRangeSnapshot? = nil) -> HistoryActivityStats {
        HistoryInsights.activityStats(selection: selection, fixedRange: fixedRange, daily: daily, summary: summary, todayKey: todayKey)
    }

    /// The top tools and models over `days` (`HistoryBreakdown`).
    func topClients(_ days: [HubHistoryDay], limit: Int = 5) -> [HistoryBreakdownRow] {
        HistoryBreakdown.topClients(daily: days, limit: limit)
    }

    func topModels(_ days: [HubHistoryDay], limit: Int = 5) -> [HistoryBreakdownRow] {
        HistoryBreakdown.topModels(daily: days, limit: limit)
    }

    // MARK: Update flow

    private func apply(stats newStats: HubStats?, scope newScope: DeviceScope, connection newConnection: HubConnection?, aliases: AliasInput) {
        let previousKey = connection?.snapshotKey
        let newKey = newConnection?.snapshotKey
        if previousKey != newKey {
            // Another Hub's History must not stay on screen or in the widget.
            if previousKey != nil {
                resetState()
                clearActivity()
            }
            forceActivityReload = true
        }
        if previousKey != newKey {
            stats = newStats
        } else if let newStats {
            stats = newStats
        }
        connection = newConnection
        if newScope != requestedScope {
            requestedScope = newScope
            forceActivityReload = true
        }
        if aliases != aliasInput {
            aliasInput = aliases
            aliasVersion += 1
            reproject()
        }
        recompute()
        reconcile()
    }

    private func resetState() {
        generation += 1
        aggregate.cancelWork()
        records.cancelWork()
        aggregate = Source()
        records = Source()
        projectionTask?.cancel()
        projectionTask = nil
        projection = nil
        pendingActivityTask?.cancel()
        pendingActivityTask = nil
        pendingActivity = nil
        lastActivity = nil
        lastActivityWrite = nil
        forceActivityReload = true
        activityWriteDue = false
        if lastError != nil { lastError = nil }
        recompute()
    }

    /// The scope actually shown: a scoped device the Hub no longer lists
    /// falls back to all devices, like every other surface.
    private var effectiveScope: DeviceScope {
        guard let id = requestedScope.deviceID else { return .all }
        guard let stats else { return requestedScope }
        return stats.device(id: id) == nil ? .all : requestedScope
    }

    private var needsAggregate: Bool { requested && effectiveScope.isAll }
    private var needsRecords: Bool { (requested && !effectiveScope.isAll) || recordsRequested }

    /// Starts whatever the current scope needs and is not loaded for the
    /// current revisions.
    private func reconcile(force: Bool = false) {
        if needsAggregate { reconcile(.aggregate, force: force) }
        if needsRecords { reconcile(.records, force: force) }
    }

    private func reconcile(_ kind: SourceKind, force: Bool) {
        guard let connection else { return }
        switch kind {
        case .aggregate:
            guard !aggregate.unsupported, aggregate.task == nil else { return }
            guard aggregate.cacheChecked else { return readCache(.aggregate, hubKey: connection.snapshotKey) }
            guard let stats else { return }
            let signature = Self.aggregateSignature(stats)
            if !force, let attempted = aggregate.attemptedSignature, signature.isEmpty || signature == attempted { return }
            aggregate.retryTask?.cancel()
            aggregate.retryTask = nil
            fetch(.aggregate, signature: signature, connection: connection, previewHasDays: !stats.history.isEmpty)
        case .records:
            guard !records.unsupported, records.task == nil else { return }
            guard records.cacheChecked else { return readCache(.records, hubKey: connection.snapshotKey) }
            guard let stats else { return }
            let signature = Self.recordsSignature(stats, now: Date())
            if !force, let attempted = records.attemptedSignature, signature == attempted { return }
            records.retryTask?.cancel()
            records.retryTask = nil
            fetch(.records, signature: signature, connection: connection, previewHasDays: false)
        }
    }

    // MARK: Disk cache

    private func readCache(_ kind: SourceKind, hubKey: String) {
        let generation = self.generation
        switch kind {
        case .aggregate:
            let cache = historyCache
            aggregate.task = Task { [weak self] in
                let entry = await Self.readHistoryCache(cache, hubKey: hubKey)
                guard let self, generation == self.generation else { return }
                self.aggregate.task = nil
                self.aggregate.cacheChecked = true
                if let entry, self.aggregate.raw == nil {
                    self.aggregate.raw = entry.value
                    self.aggregate.token += 1
                    self.aggregate.loadedSignature = entry.revision
                    self.aggregate.attemptedSignature = entry.revision
                    self.aggregate.loadedAt = entry.savedAt
                    self.reproject()
                }
                self.recompute()
                self.reconcile()
            }
        case .records:
            let cache = devicesCache
            records.task = Task { [weak self] in
                let entry = await Self.readRecordsCache(cache, hubKey: hubKey)
                guard let self, generation == self.generation else { return }
                self.records.task = nil
                self.records.cacheChecked = true
                if let entry, self.records.raw == nil {
                    self.records.raw = entry.value
                    self.records.token += 1
                    self.records.loadedSignature = entry.revision
                    self.records.attemptedSignature = entry.revision
                    self.records.loadedAt = entry.savedAt
                    self.reproject()
                }
                self.recompute()
                self.reconcile()
            }
        }
    }

    private struct CachedValue<Value: Sendable>: Sendable {
        var value: Value
        var revision: String?
        var savedAt: Date
    }

    private nonisolated static func readHistoryCache(_ cache: HubResponseCache, hubKey: String) async -> CachedValue<HubHistory>? {
        guard let entry = cache.load(hubKey: hubKey), let history = try? HubHistory.decode(from: entry.body) else { return nil }
        return CachedValue(value: history, revision: entry.header.revision, savedAt: entry.header.savedAt)
    }

    private nonisolated static func readRecordsCache(_ cache: HubResponseCache, hubKey: String) async -> CachedValue<[DeviceHistoryRecord]>? {
        guard let entry = cache.load(hubKey: hubKey),
              let list = try? DeviceHistoryRecord.decodeList(from: entry.body) else { return nil }
        return CachedValue(value: list, revision: entry.header.revision, savedAt: entry.header.savedAt)
    }

    // MARK: Fetching

    private func fetch(_ kind: SourceKind, signature: String, connection: HubConnection, previewHasDays: Bool) {
        let client = HubClient(connection: connection, session: session)
        let generation = self.generation
        let hubKey = connection.snapshotKey
        switch kind {
        case .aggregate:
            aggregate.attemptedSignature = signature
            let cache = historyCache
            aggregate.task = Task { [weak self] in
                let outcome = await Self.fetchHistory(client)
                guard let self, generation == self.generation else { return }
                self.aggregate.task = nil
                self.finishAggregate(outcome, signature: signature, previewHasDays: previewHasDays, cache: cache, hubKey: hubKey)
            }
        case .records:
            records.attemptedSignature = signature
            let cache = devicesCache
            records.task = Task { [weak self] in
                let outcome = await Self.fetchRecords(client)
                guard let self, generation == self.generation else { return }
                self.records.task = nil
                self.finishRecords(outcome, signature: signature, cache: cache, hubKey: hubKey)
            }
        }
        recompute()
    }

    private nonisolated static func fetchHistory(_ client: HubClient) async -> FetchOutcome<HubHistory> {
        do {
            let data = try await client.historyData()
            return .success(try HubHistory.decode(from: data), data)
        } catch {
            return outcome(of: error)
        }
    }

    private nonisolated static func fetchRecords(_ client: HubClient) async -> FetchOutcome<[DeviceHistoryRecord]> {
        do {
            let data = try await client.data(for: .devices)
            return .success(try DeviceHistoryRecord.decodeList(from: data), data)
        } catch {
            return outcome(of: error)
        }
    }

    private nonisolated static func outcome<Value: Sendable>(of error: Error) -> FetchOutcome<Value> {
        if error is CancellationError { return .cancelled }
        guard let error = error as? HubClientError else { return .failure(.transport(error.localizedDescription)) }
        return error.isUnsupportedEndpoint ? .unsupported : .failure(error)
    }

    private func finishAggregate(
        _ outcome: FetchOutcome<HubHistory>,
        signature: String,
        previewHasDays: Bool,
        cache: HubResponseCache,
        hubKey: String
    ) {
        switch outcome {
        case .success(let history, let body):
            // `homeHistoryFetchOutcome`: an empty answer while the preview
            // shows usage is a race (a restarting Hub), not "no History".
            if !history.daily.isEmpty || !previewHasDays {
                aggregate.raw = history
                aggregate.token += 1
                aggregate.loadedSignature = signature
                aggregate.loadedAt = Date()
                aggregate.failed = false
                aggregate.clearRetries()
                lastError = nil
                cache.saveInBackground(body: body, hubKey: hubKey, revision: signature)
                reproject()
            } else {
                aggregate.failed = true
                scheduleRetry(.aggregate, signature: signature)
            }
        case .unsupported:
            aggregate.unsupported = true
            aggregate.failed = false
            aggregate.clearRetries()
            activityWriteDue = true
        case .failure(let error):
            aggregate.failed = true
            lastError = error
            scheduleRetry(.aggregate, signature: signature)
        case .cancelled:
            break
        }
        recompute()
        reconcile()
    }

    private func finishRecords(
        _ outcome: FetchOutcome<[DeviceHistoryRecord]>,
        signature: String,
        cache: HubResponseCache,
        hubKey: String
    ) {
        switch outcome {
        case .success(let list, let body):
            records.raw = list
            records.token += 1
            records.loadedSignature = signature
            records.loadedAt = Date()
            records.failed = false
            lastError = nil
            cache.saveInBackground(body: body, hubKey: hubKey, revision: signature)
            reproject()
            // `shouldRetryFixedPeriodHistory`: a device list that does not
            // match the stats' (a record still being written) is retried.
            let expected = Set((stats?.devices ?? []).map(\.id))
            if Set(list.map(\.id)) == expected {
                records.clearRetries()
            } else {
                scheduleRetry(.records, signature: signature)
            }
        case .unsupported:
            records.unsupported = true
            records.failed = false
            records.clearRetries()
        case .failure(let error):
            records.failed = true
            lastError = error
            scheduleRetry(.records, signature: signature)
        case .cancelled:
            break
        }
        recompute()
        reconcile()
    }

    private func scheduleRetry(_ kind: SourceKind, signature: String) {
        let allowed: Bool
        switch kind {
        case .aggregate: allowed = aggregate.takeRetry(for: signature, limit: Self.maxRetries)
        case .records: allowed = records.takeRetry(for: signature, limit: Self.maxRetries)
        }
        guard allowed else { return }
        let generation = self.generation
        let retry = Task { [weak self] in
            try? await Task.sleep(for: HistoryStore.retryDelay)
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.retryFired(kind, signature: signature)
        }
        switch kind {
        case .aggregate:
            aggregate.retryTask?.cancel()
            aggregate.retryTask = retry
        case .records:
            records.retryTask?.cancel()
            records.retryTask = retry
        }
    }

    private func retryFired(_ kind: SourceKind, signature: String) {
        guard let stats else { return }
        switch kind {
        case .aggregate:
            aggregate.retryTask = nil
            // Only while that revision is still current and not loaded since.
            guard needsAggregate, Self.aggregateSignature(stats) == signature,
                  aggregate.loadedSignature != signature || aggregate.failed else { return recompute() }
            reconcile(.aggregate, force: true)
        case .records:
            records.retryTask = nil
            guard needsRecords, Self.recordsSignature(stats, now: Date()) == signature else { return recompute() }
            reconcile(.records, force: true)
        }
    }

    // MARK: Signatures

    /// `homeHistorySignature`: the Hub's History revision (without the
    /// `:aliases:` suffix presented stats carry: aliases re-project, they do
    /// not refetch); for a Hub without revisions the whole preview; `""` for
    /// an account with no History at all (never polled).
    static func aggregateSignature(_ stats: HubStats) -> String {
        if let revision = baseRevision(stats.historyRevision) { return revision }
        guard !stats.history.isEmpty else { return "" }
        var parts = stats.history.map { "\($0.date):\($0.tokens):\($0.costUsd):\($0.activeTimeMs ?? 0):\($0.unpricedTokens ?? 0)" }
        parts += stats.historyMonths.map { "\($0.month):\($0.tokens):\($0.costUsd)" }
        return "preview|" + parts.joined(separator: ",")
    }

    /// `fixedPeriodHistorySignature`: the device History revision, the
    /// phone's day and the device inventory.
    static func recordsSignature(_ stats: HubStats, now: Date) -> String {
        let revision = baseRevision(stats.deviceHistoryRevision) ?? baseRevision(stats.historyRevision) ?? ""
        let inventory = Set(stats.devices.map(\.id)).sorted().joined(separator: ",")
        return "\(revision)|\(DayKey.string(from: now, calendar: .current))|\(inventory)"
    }

    private static func baseRevision(_ revision: String?) -> String? {
        guard var value = revision?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let suffix = value.range(of: ":aliases:") { value = String(value[..<suffix.lowerBound]) }
        return value.isEmpty ? nil : value
    }

    // MARK: Aliases

    private func reproject() {
        let input: ProjectionInput
        switch aliasInput {
        case .document(let document):
            input = ProjectionInput(aggregate: aggregate.raw, records: records.raw, document: document, resolver: nil, usesResolver: false)
        case .resolver(let resolver):
            input = ProjectionInput(aggregate: aggregate.raw, records: records.raw, document: nil, resolver: resolver, usesResolver: true)
        }
        let tokens = (aggregate.token, records.token, aliasVersion)
        let generation = self.generation
        projectionTask?.cancel()
        projectionTask = Task { [weak self] in
            let result = await Self.project(input)
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.projectionTask = nil
            // New History (a load or an alias change) reaches the widget at once.
            self.activityWriteDue = true
            self.projection = Projection(
                aggregateToken: tokens.0,
                recordsToken: tokens.1,
                aliasVersion: tokens.2,
                aggregate: result.aggregate,
                records: result.records,
                resolver: result.resolver
            )
            self.recompute()
        }
    }

    private struct ProjectionResult: Sendable {
        var aggregate: HubHistory?
        var records: [String: DeviceHistoryRecord]
        var resolver: ModelAliasResolver?
    }

    /// Off the main actor: History can hold a year of per-model buckets.
    private nonisolated static func project(_ input: ProjectionInput) async -> ProjectionResult {
        let list = input.records ?? []
        let resolver = input.usesResolver
            ? input.resolver.flatMap { $0.isActive ? $0 : nil }
            : ModelAliasResolver.forHistory(input.aggregate, records: list, document: input.document)
        let aggregate = input.aggregate.map { history in resolver.map(history.projectingModelAliases) ?? history }
        var byID: [String: DeviceHistoryRecord] = [:]
        for record in list where byID[record.id] == nil {
            byID[record.id] = resolver.map(record.projectingModelAliases) ?? record
        }
        return ProjectionResult(aggregate: aggregate, records: byID, resolver: resolver)
    }

    /// A live period as History reads it: aliases folded with the History
    /// resolver; sessions and projects dropped (the History row never reads
    /// them, and folding them on every stream frame is wasted work).
    private func liveToday(_ period: UsagePeriod?) -> UsagePeriod? {
        guard var period else { return nil }
        period.sessions = []
        period.projects = []
        guard let resolver = projection?.resolver else { return period }
        return period.projectingModelAliases(resolver)
    }

    // MARK: Derivation

    /// Re-derives what views read from the loaded sources, the scope and the
    /// latest stats, then keeps the Activity widget's file current.
    private func recompute(now: Date = Date()) {
        let effective = effectiveScope
        let phoneToday = DayKey.string(from: now, calendar: .current)
        var nextPhase = Phase.idle
        var nextHistory: HubHistory?
        var nextPreview = false
        var nextAvailable = false
        var nextDaily: [HubHistoryDay] = []
        var nextToday = phoneToday
        var nextLoadedAt: Date?
        var nextRecordsLoaded = false

        // The projection includes records once it was built after a load.
        let projectedRecords = projection.flatMap { $0.recordsToken > 0 ? $0.records : nil }
        nextRecordsLoaded = projectedRecords != nil
        let nextRecordsUnavailable = projectedRecords == nil && (records.unsupported || records.failed)

        if connection != nil, requested {
            if let deviceID = effective.deviceID {
                if let projectedRecords {
                    if let record = projectedRecords[deviceID], record.historyAvailable, let history = record.history {
                        nextHistory = history
                        nextAvailable = true
                        let live = liveToday(stats?.device(id: deviceID)?.detail(.today))
                        if let patched = HistorySeries.deviceDaily(record: record, liveToday: live, now: now, fallbackTodayKey: phoneToday) {
                            nextDaily = patched.daily
                            nextToday = patched.todayKey
                        } else {
                            nextDaily = history.daily
                        }
                    }
                    nextPhase = .ready
                    nextLoadedAt = records.loadedAt
                } else if records.unsupported {
                    nextPhase = .ready
                } else if records.failed {
                    nextPhase = .failed
                } else {
                    nextPhase = .loading
                }
            } else {
                if aggregate.raw != nil, let aggregateHistory = projection?.aggregate {
                    nextHistory = aggregateHistory
                    nextAvailable = true
                    nextPhase = .ready
                    nextLoadedAt = aggregate.loadedAt
                } else if aggregate.unsupported || aggregate.failed {
                    // The preview stands in (and stays while retries run).
                    if let stats {
                        let preview = HistorySeries.previewFallback(stats: stats)
                        let resolver = projection?.resolver ?? previewResolver(preview)
                        nextHistory = resolver.map(preview.projectingModelAliases) ?? preview
                        nextPreview = true
                        nextAvailable = !preview.isEmpty
                    }
                    nextPhase = aggregate.unsupported ? .ready : .failed
                } else {
                    nextPhase = .loading
                }
                if let nextHistory {
                    nextDaily = HistorySeries.dailyWithLiveToday(nextHistory.daily, todayKey: phoneToday, today: liveToday(stats?.today))
                }
            }
        }

        if phase != nextPhase { phase = nextPhase }
        if history != nextHistory { history = nextHistory }
        if isPreviewFallback != nextPreview { isPreviewFallback = nextPreview }
        if isHistoryAvailable != nextAvailable { isHistoryAvailable = nextAvailable }
        if daily != nextDaily { daily = nextDaily }
        if todayKey != nextToday { todayKey = nextToday }
        if scope != effective { scope = effective }
        if loadedAt != nextLoadedAt { loadedAt = nextLoadedAt }
        if deviceRecordsLoaded != nextRecordsLoaded { deviceRecordsLoaded = nextRecordsLoaded }
        if deviceRecordsUnavailable != nextRecordsUnavailable { deviceRecordsUnavailable = nextRecordsUnavailable }

        if nextHistory != nil, nextAvailable {
            updateActivity(daily: nextDaily, todayKey: nextToday, summary: nextHistory?.summary, now: now)
        }
    }

    /// The alias resolver for the preview when nothing is loaded yet.
    private func previewResolver(_ preview: HubHistory) -> ModelAliasResolver? {
        switch aliasInput {
        case .document(let document):
            return ModelAliasResolver.forHistory(preview, document: document)
        case .resolver(let resolver):
            return resolver.flatMap { $0.isActive ? $0 : nil }
        }
    }

    // MARK: Activity widget

    /// Writes the scope's activity for the Activity widget when it changed
    /// (at most every `activityWriteInterval` while live today moves, at once
    /// after a load, scope or Hub change), and reloads that widget kind
    /// (throttled except after a scope or Hub change).
    private func updateActivity(daily: [HubHistoryDay], todayKey: String, summary: HistorySummary?, now: Date) {
        guard activityStore != nil, let hubKey = connection?.snapshotKey else { return }
        let snapshot = ActivitySnapshot(
            daily: daily.map(\.historyDay),
            todayKey: todayKey,
            hubKey: hubKey,
            // The requested scope, so the widget (which asks for the stored
            // preference) accepts it; a missing device shows all devices,
            // as every other surface does.
            scopeDeviceID: requestedScope.deviceID,
            generatedAt: now,
            summary: summary
        )
        if let last = lastActivity, Self.sameContent(last, snapshot), !forceActivityReload,
           let written = lastActivityWrite, now.timeIntervalSince(written) < Self.activityRefreshInterval {
            return
        }
        if forceActivityReload || activityWriteDue || lastActivity == nil {
            writeActivity(snapshot, now: now)
            return
        }
        let elapsed = lastActivityWrite.map { now.timeIntervalSince($0) } ?? .infinity
        if elapsed < 0 || elapsed >= Self.activityWriteInterval {
            writeActivity(snapshot, now: now)
            return
        }
        pendingActivity = snapshot
        guard pendingActivityTask == nil else { return }
        let delay = Self.activityWriteInterval - elapsed
        let generation = self.generation
        pendingActivityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.pendingActivityTask = nil
            if let pending = self.pendingActivity { self.writeActivity(pending, now: Date()) }
        }
    }

    private func writeActivity(_ snapshot: ActivitySnapshot, now: Date) {
        pendingActivityTask?.cancel()
        pendingActivityTask = nil
        pendingActivity = nil
        activityWriteDue = false
        guard let activityStore else { return }
        do {
            try activityStore.save(snapshot)
        } catch {
            // The widget keeps the previous file; the next change tries again.
            return
        }
        lastActivity = snapshot
        lastActivityWrite = now
        let force = forceActivityReload
        forceActivityReload = false
        if !force, let last = lastActivityReload, now.timeIntervalSince(last) >= 0,
           now.timeIntervalSince(last) < Self.activityReloadInterval { return }
        lastActivityReload = now
        WidgetCenter.shared.reloadTimelines(ofKind: ActivitySnapshot.widgetKind)
    }

    private func clearActivity() {
        pendingActivityTask?.cancel()
        pendingActivityTask = nil
        pendingActivity = nil
        lastActivity = nil
        lastActivityWrite = nil
        guard let activityStore else { return }
        try? activityStore.clear()
        lastActivityReload = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: ActivitySnapshot.widgetKind)
    }

    private static func sameContent(_ lhs: ActivitySnapshot, _ rhs: ActivitySnapshot) -> Bool {
        var aligned = lhs
        aligned.generatedAt = rhs.generatedAt
        return aligned == rhs
    }
}
