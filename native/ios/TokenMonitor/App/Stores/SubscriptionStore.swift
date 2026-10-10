import Foundation
import Observation
import TokenMonitorKit

/// The Hub's shared subscription list (`GET /api/subscriptions`), read-only.
///
/// Follows the desktop's `maybeAdoptSharedSubscriptionRevision`: every stats
/// payload carries the list's version (`subscriptionsUpdatedAt`), and the list
/// is fetched only when that version differs from the one held. A missing
/// version is no news (an older Hub; it is asked once, then on refresh), `""`
/// is a Hub that has never stored a list (empty, nothing to fetch), and the
/// same version is not retried within a minute (`SUBSCRIPTION_RETRY_MS`).
/// The last list is cached on disk per Hub, so a relaunch shows it at once.
@MainActor
@Observable
final class SubscriptionStore {
    enum Phase: Equatable, Sendable {
        /// No Hub, or nothing asked yet.
        case idle
        /// The first load is in flight and no list is held.
        case loading
        case ready
        /// The Hub has no `/api/subscriptions` (404/405).
        case unsupported
        /// The load failed and no list is held.
        case failed
    }

    /// The Hub's list (normalized by the Kit), nil until loaded.
    private(set) var document: SubscriptionDocument?
    private(set) var phase: Phase = .idle
    /// The last failure, kept while an older list stays on screen.
    private(set) var lastError: HubClientError?
    private(set) var loadedAt: Date?
    /// A fetch is in flight.
    private(set) var isLoading = false

    /// The subscriptions, `[]` until loaded.
    var subscriptions: [HubSubscription] { document?.subscriptions ?? [] }

    /// `SUBSCRIPTION_RETRY_MS`: the same version is not fetched again sooner.
    static let retryInterval: TimeInterval = 60

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cache: HubResponseCache
    @ObservationIgnored private var connection: HubConnection?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cacheChecked = false
    @ObservationIgnored private var lastAttempt: (version: String?, at: Date)?
    /// The version the Hub advertised last (nil: no stamp).
    @ObservationIgnored private var advertised: String?

    init(session: URLSession = .shared, cache: HubResponseCache = HubResponseCache(name: "subscriptions")) {
        self.session = session
        self.cache = cache
    }

    /// Feeds each stats update. Fetches when the advertised version differs
    /// from the held list's; a different Hub resets the store first.
    func update(stats: HubStats?, connection newConnection: HubConnection?) {
        if newConnection?.snapshotKey != connection?.snapshotKey {
            resetState()
        }
        connection = newConnection
        guard let newConnection else { return }
        loadCacheIfNeeded(hubKey: newConnection.snapshotKey)
        guard let stats else { return }
        advertised = stats.subscriptionsUpdatedAt
        reconcile(force: false)
    }

    /// Fetches the list now (pull to refresh, opening Subscriptions), even
    /// when the version has not moved.
    func refresh() async {
        guard let connection else { return }
        loadCacheIfNeeded(hubKey: connection.snapshotKey)
        if let task {
            await task.value
            return
        }
        fetch(connection: connection, version: advertised)
        await task?.value
    }

    /// Fetches once when nothing is held yet (an older Hub without the
    /// version stamp never announces a list).
    func ensureLoaded() {
        guard document == nil, task == nil, let connection else { return }
        Task { [weak self] in
            guard let self, self.document == nil, self.task == nil, self.connection == connection else { return }
            self.fetch(connection: connection, version: self.advertised)
        }
    }

    /// Forgets the list (Hub switch or disconnect); `clearingCache` (the
    /// default) also removes the on-disk copy.
    func reset(clearingCache: Bool = true) {
        resetState()
        connection = nil
        if clearingCache { cache.clear() }
    }

    // MARK: Private

    private func resetState() {
        generation += 1
        task?.cancel()
        task = nil
        cacheChecked = false
        lastAttempt = nil
        advertised = nil
        if document != nil { document = nil }
        if phase != .idle { phase = .idle }
        if lastError != nil { lastError = nil }
        if loadedAt != nil { loadedAt = nil }
        if isLoading { isLoading = false }
    }

    /// The list is small (a few KB): read synchronously the first time a
    /// Hub is seen.
    private func loadCacheIfNeeded(hubKey: String) {
        guard !cacheChecked else { return }
        cacheChecked = true
        guard document == nil, let entry = cache.load(hubKey: hubKey),
              let cached = try? SubscriptionDocument.decode(from: entry.body) else { return }
        document = cached
        loadedAt = entry.header.savedAt
        phase = .ready
    }

    private func reconcile(force: Bool) {
        guard let connection, task == nil, phase != .unsupported else { return }
        guard let version = advertised else {
            // No stamp: an older Hub. Nothing announces changes; the list is
            // read once when a view asks (`ensureLoaded`) or on refresh.
            return
        }
        if !force {
            if version == (document?.updatedAt ?? "") {
                if document == nil {
                    // `""` from a Hub that never stored a list: nothing to fetch.
                    document = .empty
                    phase = .ready
                }
                return
            }
            // `maybeAdoptSharedSubscriptionRevision`'s retry floor.
            if let lastAttempt, lastAttempt.version == version,
               Date().timeIntervalSince(lastAttempt.at) < Self.retryInterval { return }
        }
        fetch(connection: connection, version: version)
    }

    private func fetch(connection: HubConnection, version: String?) {
        let client = HubClient(connection: connection, session: session)
        let generation = self.generation
        let cache = self.cache
        let hubKey = connection.snapshotKey
        lastAttempt = (version, Date())
        isLoading = true
        if document == nil, phase != .loading { phase = .loading }
        task = Task { [weak self] in
            let outcome: Result<(SubscriptionDocument, Data), Error>
            do {
                let data = try await client.data(for: .subscriptions)
                outcome = .success((try SubscriptionDocument.decode(from: data), data))
            } catch {
                outcome = .failure(error)
            }
            guard let self, generation == self.generation else { return }
            self.task = nil
            self.isLoading = false
            switch outcome {
            case .success(let (document, body)):
                if self.document != document { self.document = document }
                self.phase = .ready
                self.lastError = nil
                self.loadedAt = Date()
                cache.saveInBackground(body: body, hubKey: hubKey, revision: document.updatedAt)
            case .failure(let error):
                if error is CancellationError { break }
                let hubError = (error as? HubClientError) ?? .transport(error.localizedDescription)
                if hubError.isUnsupportedEndpoint {
                    self.phase = .unsupported
                    self.lastError = nil
                } else {
                    self.lastError = hubError
                    if self.document == nil { self.phase = .failed }
                }
            }
            // The version may have moved while this was in flight.
            self.reconcile(force: false)
        }
    }
}
