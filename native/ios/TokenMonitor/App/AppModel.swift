import Foundation
import Observation
import SwiftUI
import TokenMonitorKit
import WidgetKit

/// App-wide state: the saved Hub connection, the latest stats and how they
/// are kept live, the display preferences every surface shares, and the
/// stores the detail screens read.
///
/// Views read `presented` (stats with model aliases and the device scope
/// applied) and format through `context` (`@Environment(\.tmFormatter)` in
/// views). They change preferences only through `updatePreferences(_:)`,
/// which also rewrites the widget/watch snapshot, sends the preferences to
/// the watch and reloads the widgets.
@MainActor
@Observable
final class AppModel {
    enum LiveState: Equatable {
        /// Not updating (backgrounded, not configured, or stopped by an error
        /// only the user can fix).
        case idle
        case connecting
        /// Receiving `GET /api/stats/stream` (refresh mode Live).
        case streaming
        /// Live mode, but the stream kept failing; reading `GET /api/stats`
        /// every 30 s and retrying the stream now and then.
        case polling
        /// An interval refresh mode (`appRefreshSeconds`): reading
        /// `GET /api/stats` every `pollInterval` seconds, no stream.
        case periodic
    }

    // MARK: Navigation

    var selectedTab: AppTab = .overview
    /// Each tab's stack; `MainTabView` binds them.
    var navigation = AppNavigation()
    /// The Overview period. Change it with `selectPeriod(_:)`, which also
    /// switches `periodMonthMode` for a middle-segment selection and starts
    /// loading History for a fixed range.
    var selectedPeriod: PeriodSelection = .today

    // MARK: Connection and data

    private(set) var connection: HubConnection? = nil
    /// A Hub URL is saved, even when the Keychain secret is not readable yet.
    private(set) var isConfigured: Bool
    /// The Hub's stats as decoded (`.app` options: sessions, projects and
    /// every device's details), before aliases and scope.
    private(set) var stats: HubStats? = nil
    /// What the views show: `stats` with the model aliases folded and the
    /// device scope applied (`HubStats.presenting(scope:aliases:)`). Limits
    /// and the device list stay the aggregate's.
    private(set) var presented: ScopedStats? = nil
    /// The connected Hub's model-alias document (cached per Hub).
    private(set) var aliasDocument: ModelAliasDocument? = nil
    /// When this phone last received stats (not how fresh the Hub's data is).
    private(set) var lastUpdated: Date? = nil
    private(set) var issue: HubIssue? = nil
    private(set) var liveState: LiveState = .idle
    /// The live token rate (all devices, or the scoped device per
    /// `liveTokenRateScope`); nil when hidden, idle long enough, or not
    /// streaming. `idle` samples are shown dimmed until `expiresAt`.
    private(set) var liveRate: LiveTokenRateSample? = nil

    // MARK: Preferences

    private(set) var preferences: DisplayPreferences
    /// Preferences, exchange rates and UI language; injected at the root as
    /// `.tmPresentation(model.context)`.
    private(set) var context: PresentationContext

    // MARK: Stores

    let history: HistoryStore
    let subscriptions: SubscriptionStore
    let serviceStatus: ServiceStatusStore
    let hubInfo: HubInfoStore
    let exporter: ExportService

    // MARK: Derived

    var needsOnboarding: Bool { !isConfigured }

    /// The saved Hub URL, readable even while the secret is not.
    var savedBaseURL: URL? { store.baseURL }

    /// The tab bar's tabs (Status only with `showStatusTab`).
    var visibleTabs: [AppTab] { AppTab.visible(showStatusTab: preferences.showStatusTab) }

    /// The middle period segment, from `periodMonthMode`.
    var middleSelection: PeriodSelection { PeriodSelection.middle(for: preferences.periodMonthMode) }

    /// The Overview period picker's segments: today, the middle, all time.
    var periodChoices: [PeriodSelection] { [.today, middleSelection, .allTime] }

    /// Every number and cost formatted for the current preferences.
    var formatter: DisplayFormatter { context.formatter }

    /// The live rate replaces the average output speed: the preference is on
    /// and the app is in Live (SSE) mode.
    var showsLiveRate: Bool {
        preferences.showLiveTokenRate && preferences.appRefreshSeconds == .live
    }

    /// The interval of an interval refresh mode; nil in Live mode.
    var pollInterval: TimeInterval? { RefreshPolicy.appPollInterval(preferences.appRefreshSeconds) }

    /// The scoped device, when one is scoped and the Hub lists it.
    var scopedDevice: DeviceSummary? { presented?.device }

    /// The usage of the Overview's selected period.
    var selectedUsage: PeriodUsageState { usage(for: selectedPeriod) }

    // MARK: Tuning

    /// Live mode's fallback when the stream cannot be held open.
    private static let fallbackPollInterval: Duration = .seconds(30)
    private static let streamFailuresBeforePolling = 4
    /// While polling, the stream is retried every this many polls (~5 min).
    private static let pollsBetweenStreamAttempts = 10
    /// A proxy that buffers `text/event-stream` holds the first snapshot back
    /// until its idle timeout; after this grace a plain read fills the screen.
    private static let firstEventGrace: Duration = .seconds(8)
    private static let maxBackoffSeconds: Double = 30
    /// WidgetKit budgets reloads, so fresh data reloads timelines at most this
    /// often; settings changes reload immediately.
    private static let widgetReloadInterval: TimeInterval = 5 * 60
    /// Changed stats rewrite the snapshot (a protected App Group file plus the
    /// watch payload) at most this often, though the stream can change every
    /// few seconds; the latest numbers are written when the window ends.
    private static let snapshotWriteInterval: TimeInterval = 20
    /// Unchanged stats still refresh the cached snapshot's age this often.
    private static let snapshotRefreshInterval: TimeInterval = 60
    /// A failed alias sync is retried after this long (or on a new revision).
    private static let aliasSyncRetryInterval: TimeInterval = 60

    private let store: HubConnectionStore
    private let snapshotStore: SnapshotStore
    private let preferencesStore: PreferencesStore
    private let rateStore: ExchangeRateStore
    private let aliasCache: ModelAliasCache
    @ObservationIgnored private var liveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var liveGeneration = 0
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var hasActivatedOnce = false
    @ObservationIgnored private var lastWidgetReload: Date? = nil
    /// Nil until the first write since launch or the last connection change,
    /// which therefore happens at once.
    @ObservationIgnored private var lastSnapshotWrite: Date? = nil
    @ObservationIgnored private var pendingSnapshotWrite: Task<Void, Never>? = nil
    @ObservationIgnored private var liveRateTracker = LiveTokenRateGroupTracker()
    @ObservationIgnored private var liveRateExpiry: Task<Void, Never>? = nil
    @ObservationIgnored private var storeSync: Task<Void, Never>? = nil
    @ObservationIgnored private var storeSyncPending = false
    /// `hubKey|advertised alias revision` last synced.
    @ObservationIgnored private var lastAliasSyncKey: String? = nil
    @ObservationIgnored private var aliasSyncRetryAt: Date? = nil
    @ObservationIgnored private var rateRefresh: Task<Void, Never>? = nil

    init(
        store: HubConnectionStore = .shared,
        snapshotStore: SnapshotStore = .shared,
        preferencesStore: PreferencesStore = .shared,
        rateStore: ExchangeRateStore = .shared,
        aliasCache: ModelAliasCache = .shared
    ) {
        self.store = store
        self.snapshotStore = snapshotStore
        self.preferencesStore = preferencesStore
        self.rateStore = rateStore
        self.aliasCache = aliasCache
        let preferences = preferencesStore.load()
        self.preferences = preferences
        self.context = Self.makeContext(preferences, rateStore: rateStore)
        self.isConfigured = store.isConfigured
        self.history = HistoryStore()
        self.subscriptions = SubscriptionStore()
        self.serviceStatus = ServiceStatusStore()
        self.hubInfo = HubInfoStore()
        self.exporter = ExportService()
        loadConnection()
    }

    // MARK: Lifecycle

    /// Takes the app's aggregate phase (read in `TokenMonitorApp`), not one
    /// window's: on iPad another window can still be on screen.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isSceneActive = true
            // Prewarming can launch the app before the first unlock, when the
            // Keychain refuses reads; try again once the user is here.
            if connection == nil, store.isConfigured { loadConnection() }
            if !hasActivatedOnce {
                hasActivatedOnce = true
                // Re-sends the saved connection and preferences, so a newly
                // paired or reinstalled watch gets them without a settings
                // change. Never push a nil connection here: an unreadable
                // Keychain is not a disconnect.
                if let connection {
                    PhoneSessionBridge.shared.push(
                        connection: connection,
                        snapshot: snapshotStore.load(),
                        preferences: preferencesPayload()
                    )
                } else {
                    PhoneSessionBridge.shared.push(preferences: preferencesPayload())
                }
            }
            refreshExchangeRatesIfStale()
            startLiveUpdates()
        case .background:
            isSceneActive = false
            stopLiveUpdates()
            // Widgets and the watch get the numbers the app last showed.
            if pendingSnapshotWrite != nil, let connection { writeSnapshot(of: connection) }
        default:
            // `.inactive` is transient (app switcher, Control Center): keep the stream.
            break
        }
    }

    /// Opens a `tokenmonitor://` link (`DeepLink`).
    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .dashboard(let period):
            show(.overview)
            if let period { selectPeriod(period) }
        case .trends:
            show(.overview, route: .trends)
            requestHistory()
        case .limits:
            show(.limits)
        case .devices:
            show(.devices)
        case .status:
            if preferences.showStatusTab {
                show(.status)
            } else {
                show(.settings, route: .serviceStatus)
            }
        case .settings:
            show(.settings)
        }
    }

    // MARK: Navigation

    /// Pushes `route` onto `tab`'s stack (the current tab when nil) and
    /// shows that tab. The Status tab falls back to Settings while hidden.
    func navigate(to route: AppRoute, in tab: AppTab? = nil) {
        let target = visibleTab(tab ?? selectedTab)
        selectedTab = target
        navigation[target].append(route)
    }

    /// Back to `tab`'s root screen.
    func popToRoot(_ tab: AppTab) {
        navigation[tab] = NavigationPath()
    }

    /// Shows a period on the Overview. A middle-segment selection (month,
    /// week, 7D, 30D) also becomes `periodMonthMode`, as the desktop's
    /// period menu does; a fixed range starts loading History.
    func selectPeriod(_ selection: PeriodSelection) {
        if let mode = selection.monthMode, mode != preferences.periodMonthMode {
            updatePreferences { $0.periodMonthMode = mode }
        }
        selectedPeriod = selection
        if selection.isDerived { requestHistory() }
    }

    /// The usage `selection` shows: a Hub period of `presented` as is, or a
    /// fixed range derived from History (`HistoryStore.fixedRange`), which
    /// is `.loading` until History has loaded. Views showing a fixed range
    /// should also call `history.ensureLoaded()` (e.g. in `.task`).
    func usage(for selection: PeriodSelection) -> PeriodUsageState {
        guard let presented else { return .loading }
        if let kind = selection.nativeKind { return .ready(presented.stats[kind], nil) }
        let snapshot = history.fixedRange(selection, today: presented.stats.today, now: Date())
        switch snapshot.status {
        case .ready:
            return .ready(snapshot.period ?? .empty, snapshot)
        case .native:
            return .ready(presented.stats[selection.nativeKind ?? .month], nil)
        case .unavailable(let reason):
            return isHistoryPending ? .loading : .unavailable(PeriodUnavailableReason(reason))
        }
    }

    // MARK: Preferences

    /// Changes the display preferences: saves them (App Group), re-derives
    /// `context` and `presented`, rewrites the snapshot when its projection
    /// changed, sends them to the watch, reloads every widget kind, and
    /// restarts live updates when the refresh mode changed. No-op when
    /// nothing changes after normalization.
    func updatePreferences(_ mutate: (inout DisplayPreferences) -> Void) {
        var next = preferences
        mutate(&next)
        next = next.normalized()
        guard next != preferences else { return }
        let previous = preferences
        storePreferences(next)
        preferencesDidChange(from: previous)
    }

    /// Shows every device, or one device, on every usage surface (widgets,
    /// watch and complications included). Limits and Devices never follow it.
    func setDeviceScope(_ scope: DeviceScope) {
        updatePreferences { $0.deviceScope = scope }
    }

    // MARK: Settings

    /// Saves a new or edited connection, then pushes it to the watch, reloads
    /// widgets and restarts live updates.
    /// - Throws: the Keychain error when the secret cannot be stored.
    func save(_ newConnection: HubConnection) throws {
        let hubChanged = store.baseURL != newConnection.baseURL
        try store.save(newConnection)
        // Numbers read through the old connection are not written for the new one.
        resetSnapshotWrites()
        if hubChanged {
            // Another Hub's numbers must not stay on screen, in widgets or on the watch.
            resetHubState()
            try? snapshotStore.clear()
            try? ActivitySnapshotStore.shared.clear()
            // Device ids are per Hub.
            if !preferences.deviceScope.isAll {
                var next = preferences
                next.deviceScope = .all
                storePreferences(next)
            }
        }
        connection = newConnection
        isConfigured = true
        issue = nil
        if hubChanged { aliasDocument = aliasCache.load(hubKey: newConnection.snapshotKey) }
        updatePresented()
        PhoneSessionBridge.shared.push(
            connection: newConnection,
            snapshot: hubChanged ? nil : snapshotStore.load(),
            preferences: preferencesPayload()
        )
        reloadWidgets(force: true)
        restartLiveUpdates()
    }

    /// Forgets the Hub on this phone, its widgets and the watch.
    func disconnect() {
        stopLiveUpdates()
        resetSnapshotWrites()
        resetHubState()
        try? store.clear()
        try? snapshotStore.clear()
        try? ActivitySnapshotStore.shared.clear()
        try? aliasCache.clear()
        if !preferences.deviceScope.isAll {
            var next = preferences
            next.deviceScope = .all
            storePreferences(next)
        }
        connection = nil
        isConfigured = store.isConfigured
        issue = nil
        selectedTab = .overview
        navigation = AppNavigation()
        PhoneSessionBridge.shared.push(connection: nil, snapshot: nil, preferences: preferencesPayload())
        reloadWidgets(force: true)
    }

    // MARK: Refresh

    /// Pull to refresh: one stats read, independent of the live loop.
    func refresh() async {
        if connection == nil, store.isConfigured { loadConnection() }
        guard let connection else {
            if !store.isConfigured { issue = HubIssue(kind: .notConfigured) }
            return
        }
        await fetchOnce(HubClient(connection: connection))
        // A refresh that worked after live updates gave up (e.g. the secret
        // was fixed on the Hub) brings them back.
        if issue == nil { startLiveUpdates() }
    }

    // MARK: Private: connection and preferences

    private func loadConnection() {
        isConfigured = store.isConfigured
        do {
            let loaded = try store.loadConnection()
            if loaded?.baseURL != connection?.baseURL || aliasDocument == nil {
                aliasDocument = loaded.flatMap { aliasCache.load(hubKey: $0.snapshotKey) }
            }
            connection = loaded
            if issue?.kind == .secretLocked { issue = nil }
        } catch {
            connection = nil
            issue = HubIssue(error: error, connection: nil)
        }
    }

    /// Drops everything read from the current Hub (numbers, aliases, the
    /// live rate, the stores' caches and the tabs' stacks).
    private func resetHubState() {
        stats = nil
        presented = nil
        lastUpdated = nil
        aliasDocument = nil
        lastAliasSyncKey = nil
        aliasSyncRetryAt = nil
        storeSync?.cancel()
        storeSync = nil
        storeSyncPending = false
        clearLiveRate()
        history.reset()
        subscriptions.reset()
        hubInfo.reset()
        navigation = AppNavigation()
    }

    /// Saves `next` (already normalized) and re-derives the context, without
    /// the snapshot, watch and widget side effects.
    private func storePreferences(_ next: DisplayPreferences) {
        preferencesStore.save(next)
        preferences = next
        context = Self.makeContext(next, rateStore: rateStore)
    }

    private func preferencesDidChange(from previous: DisplayPreferences) {
        if previous.deviceScope != preferences.deviceScope { updatePresented() }
        if selectedTab == .status, !preferences.showStatusTab { selectedTab = .overview }
        if selectedPeriod.monthMode != nil, selectedPeriod != middleSelection {
            selectedPeriod = middleSelection
        }
        if !showsLiveRate {
            clearLiveRate()
        } else if !(previous.showLiveTokenRate && previous.appRefreshSeconds == .live) {
            // Starts from a fresh baseline at the next snapshot.
            clearLiveRate()
        }

        // Widgets, the watch and complications only see the preferences they
        // read; an app-only change (a Home module, the period menu) costs
        // them no reload.
        if Self.sharedPart(previous) != Self.sharedPart(preferences) {
            let projectionChanged = SnapshotBuilder(preferences: previous, aliases: aliasDocument).projectionKey
                != SnapshotBuilder(preferences: preferences, aliases: aliasDocument).projectionKey
            if projectionChanged, let connection, stats != nil {
                // Pushes the preferences with the new snapshot.
                writeSnapshot(of: connection, reloadingWidgets: false)
            } else {
                PhoneSessionBridge.shared.push(preferences: preferencesPayload())
            }
            reloadWidgets(force: true)
        }

        if previous.appRefreshSeconds != preferences.appRefreshSeconds { restartLiveUpdates() }
        if previous.deviceScope != preferences.deviceScope { syncStores() }
        if selectedPeriod.isDerived { requestHistory() }
    }

    /// `preferences` with the app-only settings (§3.3 surface "A" alone) at
    /// their defaults: what widgets, the watch and complications can see.
    private static func sharedPart(_ preferences: DisplayPreferences) -> DisplayPreferences {
        let defaults = DisplayPreferences.defaults
        var shared = preferences
        shared.showCompactTotalTokens = defaults.showCompactTotalTokens
        shared.showLiveTokenRate = defaults.showLiveTokenRate
        shared.tokenRateMode = defaults.tokenRateMode
        shared.liveTokenRateScope = defaults.liveTokenRateScope
        shared.periodMonthMode = defaults.periodMonthMode
        shared.homeModuleOrder = defaults.homeModuleOrder
        shared.hiddenHomeModules = defaults.hiddenHomeModules
        shared.homeLimitAccountCount = defaults.homeLimitAccountCount
        shared.homeLimitDisplayMode = defaults.homeLimitDisplayMode
        shared.showHomeLimitBars = defaults.showHomeLimitBars
        shared.showHomeLimitProviderNames = defaults.showHomeLimitProviderNames
        shared.modelRankingMetric = defaults.modelRankingMetric
        shared.showLimitSource = defaults.showLimitSource
        shared.maskLimitAccountEmails = defaults.maskLimitAccountEmails
        shared.sessionTitlesEnabled = defaults.sessionTitlesEnabled
        shared.sessionContextMetric = defaults.sessionContextMetric
        shared.appRefreshSeconds = defaults.appRefreshSeconds
        shared.serviceStatusRefreshMs = defaults.serviceStatusRefreshMs
        shared.showStatusTab = defaults.showStatusTab
        shared.hiddenServiceProviders = defaults.hiddenServiceProviders
        shared.serviceProviderDisplayOrder = defaults.serviceProviderDisplayOrder
        return shared
    }

    private static func makeContext(_ preferences: DisplayPreferences, rateStore: ExchangeRateStore) -> PresentationContext {
        PresentationContext(
            preferences: preferences,
            rates: CurrencyRates.resolve(cache: rateStore.load(), overrides: preferences.currencyRates),
            languageIdentifier: PresentationContext.languageIdentifier(of: .main)
        )
    }

    /// What the watch stores: the preferences and the exchange-rate cache.
    private func preferencesPayload() -> PreferencesPayload {
        PreferencesPayload(preferences: preferences, rateCacheData: rateStore.data())
    }

    private func refreshExchangeRatesIfStale() {
        guard rateRefresh == nil else { return }
        rateRefresh = Task { [weak self] in
            await ExchangeRateRefresher.refreshIfStale()
            guard let self else { return }
            self.rateRefresh = nil
            self.ratesMayHaveChanged()
        }
    }

    /// New rates change every cost shown, in widgets and on the watch too.
    private func ratesMayHaveChanged() {
        let next = Self.makeContext(preferences, rateStore: rateStore)
        guard next != context else { return }
        context = next
        PhoneSessionBridge.shared.push(preferences: preferencesPayload())
        reloadWidgets(force: true)
    }

    private func visibleTab(_ tab: AppTab) -> AppTab {
        tab == .status && !preferences.showStatusTab ? .settings : tab
    }

    /// Shows `tab` at its root, or with `route` pushed.
    private func show(_ tab: AppTab, route: AppRoute? = nil) {
        let target = visibleTab(tab)
        selectedTab = target
        navigation[target] = route.map { NavigationPath([$0]) } ?? NavigationPath()
    }

    // MARK: Private: stats

    private func apply(_ newStats: HubStats, from source: HubConnection, viaStream: Bool) {
        // A response from a connection that has since been replaced or removed.
        guard source == connection else { return }
        let now = Date()
        let changed = newStats != stats
        if changed {
            stats = newStats
            updatePresented()
        }
        lastUpdated = now
        if issue != nil { issue = nil }
        if viaStream { observeLiveRate() }
        syncStores()
        updateSnapshot(changed: changed, from: source, now: now)
    }

    private func updatePresented() {
        let next = stats?.presenting(scope: preferences.deviceScope, aliases: aliasDocument)
        if next != presented { presented = next }
    }

    private var isHistoryPending: Bool {
        if case .loading = history.phase { return true }
        if case .idle = history.phase { return true }
        return false
    }

    private func requestHistory() {
        guard connection != nil else { return }
        Task { [history] in
            await history.ensureLoaded()
        }
    }

    /// After new stats: model aliases (when the Hub advertises a new
    /// revision), then History and subscriptions (each refetches only when
    /// its revision or the scope changed). One run at a time; stats that
    /// arrive meanwhile run once more afterwards.
    private func syncStores() {
        guard storeSync == nil else {
            storeSyncPending = true
            return
        }
        guard let connection, stats != nil else { return }
        storeSync = Task { [weak self] in
            await self?.runStoreSync(connection: connection)
            guard let self, !Task.isCancelled else { return }
            self.storeSync = nil
            if self.storeSyncPending {
                self.storeSyncPending = false
                self.syncStores()
            }
        }
    }

    private func runStoreSync(connection source: HubConnection) async {
        guard source == connection, let stats else { return }
        let revision = SharedSettingsKind.modelAliases.advertisedRevision(in: stats.syncSettingsRevisions)
        let aliasKey = source.snapshotKey + "|" + (revision.map(String.init) ?? "-")
        let now = Date()
        if aliasKey != lastAliasSyncKey, aliasSyncRetryAt.map({ now >= $0 }) ?? true {
            let document = await AliasSync.update(stats: stats, connection: source)
            guard !Task.isCancelled, source == connection else { return }
            if let document {
                lastAliasSyncKey = aliasKey
                aliasSyncRetryAt = nil
                if document != aliasDocument {
                    aliasDocument = document
                    aliasesDidChange()
                }
            } else {
                aliasSyncRetryAt = now.addingTimeInterval(Self.aliasSyncRetryInterval)
            }
        }
        guard !Task.isCancelled, source == connection, let latest = self.stats else { return }
        await history.update(stats: latest, scope: preferences.deviceScope, connection: source, resolver: aliasDocument)
        guard !Task.isCancelled, source == connection, let latest = self.stats else { return }
        await subscriptions.update(stats: latest, connection: source)
    }

    /// New aliases change every model row, the snapshot's projection and the
    /// live rate's model keys.
    private func aliasesDidChange() {
        updatePresented()
        clearLiveRate()
        if let connection, stats != nil { writeSnapshot(of: connection) }
    }

    // MARK: Private: live rate

    private func observeLiveRate() {
        guard showsLiveRate, let presented, let connection else { return }
        let selection = LiveTokenRate.selection(
            stats: presented.stats,
            rateScope: preferences.liveTokenRateScope,
            deviceScope: preferences.deviceScope
        )
        let aliasKey = aliasDocument.map { String($0.revision) } ?? "-"
        let result = liveRateTracker.observe(selection, context: connection.snapshotKey + "|" + aliasKey)
        setLiveRate(result.sample)
    }

    private func setLiveRate(_ sample: LiveTokenRateSample?) {
        if sample != liveRate { liveRate = sample }
        liveRateExpiry?.cancel()
        liveRateExpiry = nil
        guard let expiresAt = sample?.expiresAt else { return }
        // Just past the expiry, as the desktop does (+10 ms).
        let delay = max(0.05, expiresAt.timeIntervalSinceNow + 0.01)
        liveRateExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // The reading goes idle (dimmed) or clears without a new snapshot.
            self.setLiveRate(self.liveRateTracker.currentSample())
        }
    }

    private func clearLiveRate() {
        liveRateTracker.clear()
        liveRateExpiry?.cancel()
        liveRateExpiry = nil
        if liveRate != nil { liveRate = nil }
    }

    // MARK: Private: snapshot and widgets

    /// Writes the snapshot now, schedules the latest numbers for the end of
    /// the write window, or does nothing.
    private func updateSnapshot(changed: Bool, from source: HubConnection, now: Date) {
        guard let last = lastSnapshotWrite else {
            // First numbers since launch or a connection change.
            writeSnapshot(of: source)
            return
        }
        let elapsed = now.timeIntervalSince(last)
        // `elapsed < 0`: the clock moved back; do not wait for it to catch up.
        let interval = changed ? Self.snapshotWriteInterval : Self.snapshotRefreshInterval
        if elapsed < 0 || elapsed >= interval {
            writeSnapshot(of: source)
        } else if changed, pendingSnapshotWrite == nil {
            let delay = Self.snapshotWriteInterval - elapsed
            pendingSnapshotWrite = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.pendingSnapshotWrite = nil
                self.writeSnapshot(of: source)
            }
        }
    }

    /// Saves the current stats as the App Group snapshot (built by
    /// `SnapshotBuilder` with the current preferences and aliases), hands it
    /// and the preferences to the watch and reloads widgets (throttled),
    /// unless `source` is no longer the connection they came from.
    private func writeSnapshot(of source: HubConnection, reloadingWidgets: Bool = true) {
        pendingSnapshotWrite?.cancel()
        pendingSnapshotWrite = nil
        guard source == connection, let stats else { return }
        let now = Date()
        lastSnapshotWrite = now
        let snapshot = SnapshotBuilder(preferences: preferences, aliases: aliasDocument)
            .snapshot(from: stats, fetchedAt: lastUpdated ?? now, hub: source)
        // On failure widgets keep the previous file; the next due write tries again.
        try? snapshotStore.save(snapshot)
        PhoneSessionBridge.shared.push(connection: source, snapshot: snapshot, preferences: preferencesPayload())
        if reloadingWidgets { reloadWidgets(force: false, now: now) }
    }

    private func resetSnapshotWrites() {
        pendingSnapshotWrite?.cancel()
        pendingSnapshotWrite = nil
        lastSnapshotWrite = nil
    }

    /// Every widget kind, the Activity widget (`ActivitySnapshot.widgetKind`)
    /// included.
    private func reloadWidgets(force: Bool, now: Date = Date()) {
        if !force, let last = lastWidgetReload, now.timeIntervalSince(last) < Self.widgetReloadInterval { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Private: fetching

    @discardableResult
    private func fetchOnce(_ client: HubClient) async -> HubIssue? {
        do {
            let stats = try await client.stats(options: .app)
            apply(stats, from: client.connection, viaStream: false)
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            guard client.connection == connection else { return nil }
            let failure = HubIssue(error: error, connection: client.connection)
            issue = failure
            return failure
        }
    }

    // MARK: Private: live updates

    private func startLiveUpdates() {
        guard isSceneActive, liveTask == nil, let connection else { return }
        liveGeneration += 1
        let generation = liveGeneration
        let interval = pollInterval
        liveTask = Task { [weak self] in
            if let interval {
                await self?.runPeriodicUpdates(connection: connection, interval: interval)
            } else {
                await self?.runLiveUpdates(connection: connection)
            }
            self?.liveUpdatesEnded(generation: generation)
        }
    }

    private func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        liveGeneration += 1
        liveState = .idle
        // The next stream starts from a fresh baseline: a delta across the
        // gap would not be a live rate.
        clearLiveRate()
    }

    private func restartLiveUpdates() {
        stopLiveUpdates()
        startLiveUpdates()
    }

    private func liveUpdatesEnded(generation: Int) {
        // A cancelled run must not clear the task that replaced it.
        guard generation == liveGeneration else { return }
        liveTask = nil
        liveState = .idle
    }

    /// Interval mode: one stats read every `interval` seconds while active,
    /// no stream. Numbers younger than one interval (a quick app switch) are
    /// not read again at once. Stops on errors only new settings can fix.
    private func runPeriodicUpdates(connection: HubConnection, interval: TimeInterval) async {
        let client = HubClient(connection: connection)
        liveState = .periodic
        if let lastUpdated {
            let wait = min(interval, interval - Date().timeIntervalSince(lastUpdated))
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
        }
        while !Task.isCancelled {
            if let failure = await fetchOnce(client), failure.stopsLiveUpdates { return }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// Live mode: streams while it works, reconnecting with capped
    /// exponential backoff and jitter; polls when the stream keeps failing;
    /// stops on errors that only new settings can fix.
    private func runLiveUpdates(connection: HubConnection) async {
        let client = HubClient(connection: connection)
        var failures = 0
        while !Task.isCancelled {
            if failures >= Self.streamFailuresBeforePolling {
                liveState = .polling
                for _ in 0..<Self.pollsBetweenStreamAttempts {
                    if let failure = await fetchOnce(client), failure.stopsLiveUpdates { return }
                    try? await Task.sleep(for: Self.fallbackPollInterval)
                    if Task.isCancelled { return }
                }
                // One more stream failure puts it straight back to polling.
                failures = Self.streamFailuresBeforePolling - 1
                continue
            }

            liveState = .connecting
            let outcome = await consumeStream(client)
            if Task.isCancelled { return }
            if let error = outcome.error {
                let failure = HubIssue(error: error, connection: connection)
                if failure.stopsLiveUpdates {
                    issue = failure
                    return
                }
                // A single drop (a Hub restart) reconnects quietly; keep showing
                // the last numbers and only report a failure that persists.
                if outcome.receivedStats {
                    failures = 0
                } else {
                    failures += 1
                    if stats == nil || failures >= 2 { issue = failure }
                }
            } else {
                // The Hub closed the stream cleanly; reconnect soon.
                failures = outcome.receivedStats ? 0 : failures + 1
            }
            liveState = .connecting
            try? await Task.sleep(for: Self.backoff(afterFailures: failures))
        }
    }

    private func consumeStream(_ client: HubClient) async -> (receivedStats: Bool, error: Error?) {
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.firstEventGrace)
            guard !Task.isCancelled else { return }
            await self?.fetchOnce(client)
        }
        defer { watchdog.cancel() }
        var received = false
        do {
            for try await update in client.statsStream(options: .app) {
                if Task.isCancelled { break }
                if !received {
                    received = true
                    watchdog.cancel()
                    liveState = .streaming
                }
                apply(update, from: client.connection, viaStream: true)
            }
            return (received, nil)
        } catch {
            return (received, error)
        }
    }

    private static func backoff(afterFailures failures: Int) -> Duration {
        let exponent = min(max(failures - 1, 0), 6)
        let base = min(maxBackoffSeconds, pow(2, Double(exponent)))
        // Jitter keeps several phones (or a phone and its watch) from
        // reconnecting to a restarted Hub in lockstep.
        let jittered = base + Double.random(in: 0...(base * 0.3))
        return .milliseconds(Int(jittered * 1000))
    }
}
