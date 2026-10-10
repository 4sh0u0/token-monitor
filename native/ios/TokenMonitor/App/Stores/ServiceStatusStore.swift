import Foundation
import Observation
import TokenMonitorKit

/// The vendors' public status pages (Claude, OpenAI, Cursor, DeepSeek) for
/// the Status tab, read straight from their Statuspage JSON (never through
/// the Hub).
///
/// Follows the desktop renderer (`refreshServiceStatus`,
/// `maybeFetchServiceStatus`): only the visible providers are asked for, in
/// the user's order (`serviceProviderDisplayOrder`, `hiddenServiceProviders`
/// through `OrderedIDs`, like `serviceStatusProviderPreferences.js`); the
/// first visit checks at once; while the tab is visible (`start`/`stop`) a
/// re-check runs every `serviceStatusRefreshMs` (none when Manual). The
/// client caches a result for 60 s (10 s after a failure), so the refresh
/// button passes `force: true`.
@MainActor
@Observable
final class ServiceStatusStore {
    /// The visible providers' summaries, in the user's order; empty until
    /// the first check.
    private(set) var summaries: [ServiceStatusSummary] = []
    /// When the last check started.
    private(set) var checkedAt: Date?
    private(set) var isLoading = false
    /// The visible providers in the user's order (for placeholder rows
    /// before the first check).
    private(set) var providers: [ServiceStatusProvider]
    /// The re-check timer runs (the Status tab is on screen).
    private(set) var isRunning = false

    /// Every provider is hidden (`serviceStatus.allHidden`).
    var allHidden: Bool { providers.isEmpty }

    @ObservationIgnored private let client: ServiceStatusClient
    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private var preferences: DisplayPreferences
    @ObservationIgnored private var report: ServiceStatusReport?
    /// When the last check was asked for (even one that did nothing).
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var interval: TimeInterval?
    /// An explicit `start(interval:)` wins over the preference.
    @ObservationIgnored private var explicitInterval: TimeInterval??
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesTask: Task<Void, Never>?

    init(
        client: ServiceStatusClient = ServiceStatusClient(userAgent: ServiceStatusClient.userAgent(appVersion: ServiceStatusStore.appVersion)),
        preferencesStore: PreferencesStore = .shared
    ) {
        self.client = client
        self.preferencesStore = preferencesStore
        let preferences = preferencesStore.load()
        self.preferences = preferences
        self.providers = Self.visibleProviders(preferences)
        self.interval = RefreshPolicy.serviceStatusInterval(preferences.serviceStatusRefreshMs)
        observePreferences()
    }

    nonisolated static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The summary of one provider from the last check.
    func summary(for providerID: String) -> ServiceStatusSummary? {
        summaries.first { $0.id == providerID }
    }

    // MARK: Checks

    /// Checks the visible providers. `force` skips the client's cache (the
    /// refresh button); otherwise a fresh cached result is reused. A check
    /// already running is joined, not repeated.
    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            guard force else { return }
        }
        lastAttemptAt = Date()
        let ids = providers.map(\.id)
        guard !ids.isEmpty else {
            if !summaries.isEmpty { summaries = [] }
            return
        }
        isLoading = true
        let client = self.client
        let task = Task { [weak self] in
            let report = await client.statuses(force: force, providerIDs: ids)
            guard let self else { return }
            self.refreshTask = nil
            self.isLoading = false
            // A cancelled check returns what it had; keep the previous one.
            guard !Task.isCancelled else { return }
            self.report = report
            self.checkedAt = report.checkedAt
            self.applyOrder()
        }
        refreshTask = task
        await task.value
    }

    /// Starts the re-check timer while the Status tab is visible: checks at
    /// once when nothing was checked yet, then every `interval` seconds after
    /// the last check (`RefreshPolicy.serviceStatusInterval`; nil = Manual,
    /// only the first check). Restarts when already running.
    func start(interval: TimeInterval?) {
        explicitInterval = .some(interval)
        self.interval = interval
        restartTimer()
    }

    /// `start` with the interval from the preferences
    /// (`serviceStatusRefreshMs`), following later changes.
    func start() {
        explicitInterval = nil
        interval = RefreshPolicy.serviceStatusInterval(preferences.serviceStatusRefreshMs)
        restartTimer()
    }

    /// Stops the timer (the Status tab left the screen or the app went to
    /// the background). Results stay for the next visit.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        if isRunning { isRunning = false }
    }

    /// Applies new preferences (order, hidden providers, re-check interval)
    /// at once; the store also follows `PreferencesStore` saves by itself.
    func apply(preferences newPreferences: DisplayPreferences) {
        let old = preferences
        preferences = newPreferences
        let nextProviders = Self.visibleProviders(newPreferences)
        let providersChanged = nextProviders.map(\.id) != providers.map(\.id)
        if providersChanged {
            providers = nextProviders
            applyOrder()
        }
        let intervalChanged = old.serviceStatusRefreshMs != newPreferences.serviceStatusRefreshMs
        if intervalChanged, explicitInterval == nil {
            interval = RefreshPolicy.serviceStatusInterval(newPreferences.serviceStatusRefreshMs)
        }
        guard isRunning else { return }
        if (intervalChanged && explicitInterval == nil) || providersChanged {
            // A new provider set is a new cache key in the client: check it.
            restartTimer(checkNow: providersChanged)
        }
    }

    /// Forgets the last check (disconnect). The timer keeps its state.
    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        report = nil
        lastAttemptAt = nil
        if !summaries.isEmpty { summaries = [] }
        if checkedAt != nil { checkedAt = nil }
        if isLoading { isLoading = false }
        Task { [client] in await client.invalidate() }
    }

    // MARK: Private

    private func restartTimer(checkNow: Bool = false) {
        timerTask?.cancel()
        isRunning = true
        let interval = self.interval
        timerTask = Task { [weak self] in
            if checkNow || self?.report == nil {
                await self?.refresh()
            }
            guard let interval, interval > 0 else { return }
            // Holds the store only while it works, not across the sleeps.
            while !Task.isCancelled, let wait = self?.secondsUntilDue(interval: interval) {
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    continue
                }
                await self?.refresh()
            }
        }
    }

    /// Seconds until the next re-check: `interval` after the last check or
    /// attempt (a manual refresh in between moves it), at least 1 s while
    /// not yet due.
    private func secondsUntilDue(interval: TimeInterval) -> TimeInterval {
        let anchors = [checkedAt, lastAttemptAt].compactMap { $0 }
        guard let last = anchors.max() else { return 0 }
        let remaining = last.addingTimeInterval(interval).timeIntervalSinceNow
        return remaining <= 0 ? 0 : max(1, remaining)
    }

    private func applyOrder() {
        guard let report else {
            if !summaries.isEmpty { summaries = [] }
            return
        }
        let byID = Dictionary(report.summaries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = providers.compactMap { byID[$0.id] }
        if ordered != summaries { summaries = ordered }
    }

    private func observePreferences() {
        let center = NotificationCenter.default
        let name = PreferencesStore.didChangeNotification
        let store = preferencesStore
        preferencesTask = Task { [weak self] in
            for await _ in center.notifications(named: name) {
                guard let self else { return }
                self.apply(preferences: store.load())
            }
        }
    }

    /// `visibleOrder(SERVICE_PROVIDER_OPTIONS, order, hidden)`.
    static func visibleProviders(_ preferences: DisplayPreferences) -> [ServiceStatusProvider] {
        let known = ServiceStatusProvider.all.map(\.id)
        let hidden = Set(OrderedIDs.normalizeSelection(preferences.hiddenServiceProviders, known: known))
        return OrderedIDs.normalizeOrder(preferences.serviceProviderDisplayOrder, known: known)
            .filter { !hidden.contains($0) }
            .compactMap(ServiceStatusProvider.provider(id:))
    }
}
