import Foundation
import Observation
import TokenMonitorKit

/// Keeps the Hub's shared model aliases (`GET /api/sync/settings/modelAliases`)
/// current through `SharedSettingsRefresher`, which also writes the App Group
/// cache (`ModelAliasCache.shared`) that widgets and complications read.
///
/// The group is fetched only when nothing is held for the Hub or the stats
/// advertise another revision (`stats.syncSettingsRevisions.modelAliases`);
/// an absent marker is no news. Calls made while a fetch runs join it (the
/// stream can deliver several frames a second), and a revision whose fetch
/// failed is not asked for again within a minute.
@MainActor
@Observable
final class AliasSync {
    /// The document to apply for the current Hub, nil when none is known.
    private(set) var document: ModelAliasDocument?
    private(set) var isRefreshing = false

    /// A failed revision is not refetched sooner (the desktop's floor for
    /// shared-list catch-up, `SUBSCRIPTION_RETRY_MS`).
    static let retryInterval: TimeInterval = 60

    @ObservationIgnored private let cache: ModelAliasCache
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var hubKey: String?
    @ObservationIgnored private var task: Task<ModelAliasDocument?, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failedRevision: (revision: Int?, at: Date)?

    init(cache: ModelAliasCache = .shared, session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    /// The cached document of `connection`'s Hub, read synchronously (for the
    /// first presentation at launch, before any network); it also becomes
    /// `document`.
    @discardableResult
    func cachedDocument(for connection: HubConnection?) -> ModelAliasDocument? {
        guard let connection else {
            reset()
            return nil
        }
        adopt(hubKey: connection.snapshotKey)
        if document == nil, let cached = cache.load(hubKey: connection.snapshotKey) {
            document = cached
        }
        return document
    }

    /// After each stats update: the document to present with these stats,
    /// fetched first when the advertised revision moved.
    func update(stats: HubStats, connection: HubConnection?) async -> ModelAliasDocument? {
        await sync(stats: stats, connection: connection, force: false)
    }

    /// Fetches the group even when the held revision is current (pull to
    /// refresh).
    @discardableResult
    func refresh(stats: HubStats, connection: HubConnection?) async -> ModelAliasDocument? {
        await sync(stats: stats, connection: connection, force: true)
    }

    /// Forgets the document (Hub switch or disconnect). `clearingCache` also
    /// removes the App Group copy (disconnect: widgets must not keep another
    /// Hub's names).
    func reset(clearingCache: Bool = false) {
        generation += 1
        task?.cancel()
        task = nil
        hubKey = nil
        failedRevision = nil
        if document != nil { document = nil }
        if isRefreshing { isRefreshing = false }
        if clearingCache { try? cache.clear() }
    }

    // MARK: Shared instance

    /// The app's alias sync (App Group cache, shared session).
    static let shared = AliasSync()

    /// `shared.update(stats:connection:)`: the plan's
    /// `AliasSync.update(stats:connection:) async -> ModelAliasDocument?`.
    /// Nil when nothing is known for the Hub (no cache and the fetch
    /// failed); a Hub without shared settings gives `.uninitialized`.
    static func update(stats: HubStats, connection: HubConnection?) async -> ModelAliasDocument? {
        await shared.update(stats: stats, connection: connection)
    }

    /// `shared.cachedDocument(for:)`.
    @discardableResult
    static func cachedDocument(for connection: HubConnection?) -> ModelAliasDocument? {
        shared.cachedDocument(for: connection)
    }

    /// `shared.refresh(stats:connection:)`.
    @discardableResult
    static func refresh(stats: HubStats, connection: HubConnection?) async -> ModelAliasDocument? {
        await shared.refresh(stats: stats, connection: connection)
    }

    /// `shared.reset(clearingCache:)`.
    static func reset(clearingCache: Bool = false) {
        shared.reset(clearingCache: clearingCache)
    }

    // MARK: Private

    private func adopt(hubKey key: String) {
        guard key != hubKey else { return }
        reset()
        hubKey = key
    }

    private func sync(stats: HubStats, connection: HubConnection?, force: Bool) async -> ModelAliasDocument? {
        guard let connection else {
            reset()
            return nil
        }
        let key = connection.snapshotKey
        adopt(hubKey: key)
        if let task { return await task.value }
        if document == nil, let cached = cache.load(hubKey: key) { document = cached }
        let advertised = SharedSettingsKind.modelAliases.advertisedRevision(in: stats.syncSettingsRevisions)
        if !force {
            guard ModelAliasDocument.needsFetch(cached: document, advertisedRevision: advertised) else { return document }
            if let failedRevision, failedRevision.revision == advertised,
               Date().timeIntervalSince(failedRevision.at) < Self.retryInterval { return document }
        }
        let client = HubClient(connection: connection, session: session)
        let cache = self.cache
        let generation = self.generation
        isRefreshing = true
        let task = Task { [weak self] () -> ModelAliasDocument? in
            let fetched = await SharedSettingsRefresher.modelAliases(stats: stats, client: client, cache: cache, hubKey: key, force: force)
            guard let self, generation == self.generation else { return fetched }
            self.task = nil
            self.isRefreshing = false
            // The refresher returns the held document when the fetch failed;
            // a revision still not held then waits for the retry floor.
            if ModelAliasDocument.needsFetch(cached: fetched, advertisedRevision: advertised) {
                self.failedRevision = (advertised, Date())
            } else {
                self.failedRevision = nil
            }
            if self.document != fetched { self.document = fetched }
            return fetched
        }
        self.task = task
        return await task.value
    }
}
