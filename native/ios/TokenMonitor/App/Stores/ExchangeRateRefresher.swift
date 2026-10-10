import Foundation
import Observation
import TokenMonitorKit

/// Keeps the daily USD exchange rates current in the App Group
/// (`ExchangeRateStore`, `exchangeRates.v1`), the way the desktop's
/// `refreshExchangeRates` does: fetch only when the cache is stale
/// (`ExchangeRateCache.isStale`: not today's UTC date and older than 24 h),
/// silently keep the last cache (or the built-in floors) on failure. Only the
/// iPhone app fetches; widgets read the cache and the watch receives it in the
/// preferences payload.
@MainActor
@Observable
final class ExchangeRateRefresher {
    /// The stored rates (nil: none fetched yet; the built-in floors apply).
    private(set) var cache: ExchangeRateCache?
    private(set) var isRefreshing = false
    /// When the last fetch failed (cleared by a success).
    private(set) var lastFailureAt: Date?

    /// After a failure the app does not ask again sooner, though activation
    /// can happen many times a minute (the desktop re-checks every 6 h).
    static let failureRetryInterval: TimeInterval = 10 * 60

    @ObservationIgnored private let store: ExchangeRateStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var task: Task<Bool, Never>?

    init(store: ExchangeRateStore = .shared, session: URLSession = .shared) {
        self.store = store
        self.session = session
        self.cache = store.load()
    }

    /// Whether `refreshIfStale` would fetch now.
    func isStale(now: Date = Date()) -> Bool {
        ExchangeRateCache.isStale(cache, now: now)
    }

    /// Fetches and stores new rates when the cache is stale (or `force`).
    /// - Returns: true when new rates were stored, so the caller re-derives
    ///   its `PresentationContext` and re-sends the preferences payload to
    ///   the watch; false when nothing changed or the fetch failed.
    @discardableResult
    func refreshIfStale(force: Bool = false, now: Date = Date()) async -> Bool {
        if let task { return await task.value }
        // Another process (or a restored backup) may have written the store.
        let stored = store.load()
        if stored != cache { cache = stored }
        guard force || ExchangeRateCache.isStale(cache, now: now) else { return false }
        if !force, let lastFailureAt, now.timeIntervalSince(lastFailureAt) >= 0,
           now.timeIntervalSince(lastFailureAt) < Self.failureRetryInterval { return false }
        isRefreshing = true
        let session = self.session
        let task = Task { [weak self] () -> Bool in
            let fetched = try? await ExchangeRateClient.fetch(session: session, now: Date())
            guard let self else { return false }
            self.task = nil
            self.isRefreshing = false
            guard let fetched else {
                self.lastFailureAt = Date()
                return false
            }
            self.lastFailureAt = nil
            self.store.save(fetched)
            let changed = fetched != self.cache
            self.cache = fetched
            return changed
        }
        self.task = task
        return await task.value
    }

    /// Re-reads the stored rates (after the watch or a settings change wrote
    /// them); nothing is fetched.
    func reload() {
        let stored = store.load()
        if stored != cache { cache = stored }
    }

    // MARK: Shared instance

    /// The app's refresher (App Group store, shared session).
    static let shared = ExchangeRateRefresher()

    /// `shared.refreshIfStale(force:)`, which the app runs at activation.
    @discardableResult
    static func refreshIfStale(force: Bool = false) async -> Bool {
        await shared.refreshIfStale(force: force)
    }
}
