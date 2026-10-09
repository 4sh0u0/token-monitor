import Foundation
import TokenMonitorKit

/// What a widget can draw.
enum WidgetDataState: Sendable {
    /// No Hub URL saved: the app has not been set up (or was disconnected).
    case notConfigured
    /// A Hub is configured, nothing is cached and the Hub could not be read.
    case unavailable
    case ready(TokenSnapshot)

    var snapshot: TokenSnapshot? {
        if case .ready(let snapshot) = self { return snapshot }
        return nil
    }
}

/// Loads what the widgets show: the App Group snapshot, refreshed from the
/// Hub when it is missing or old. Never throws and never waits longer than
/// the widget network timeout; any failure falls back to the cache.
enum SnapshotLoader {
    static func load(forceRefresh: Bool, now: Date = Date()) async -> WidgetDataState {
        let connections = HubConnectionStore.shared
        // Only the URL is read here; the Keychain is touched just before a fetch.
        guard connections.isConfigured else { return .notConfigured }
        let cached = SnapshotStore.shared.load()
        if !forceRefresh, let cached, isFresh(cached, at: now) {
            return .ready(cached)
        }
        if let fetched = await SnapshotRefresher.shared.refresh(connections: connections, force: forceRefresh, now: now) {
            return .ready(fetched)
        }
        if let cached { return .ready(cached) }
        return .unavailable
    }

    /// A snapshot dated in the future (the clock moved back) counts as old,
    /// otherwise it would never be refreshed.
    static func isFresh(_ snapshot: TokenSnapshot, at now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= -60 && age <= WidgetTiming.refreshAfter
    }
}

/// Serializes Hub fetches inside the extension process.
///
/// `reloadAllTimelines()` asks for every placed widget's timeline at once;
/// without this each one would fetch and decode its own copy of the full
/// `/api/stats` response, which is how a widget extension blows through its
/// memory limit. Concurrent callers share one fetch, and a fetch that just
/// finished is reused by callers that read the cache a moment too early.
actor SnapshotRefresher {
    static let shared = SnapshotRefresher()

    private static let reuseWindow: TimeInterval = 60

    private var inFlight: Task<TokenSnapshot?, Never>?
    private var lastFetched: TokenSnapshot?

    func refresh(connections: HubConnectionStore, force: Bool, now: Date) async -> TokenSnapshot? {
        if let inFlight {
            return await inFlight.value
        }
        if !force, let lastFetched, SnapshotLoader.isFresh(lastFetched, at: now),
           !lastFetched.isOlder(than: Self.reuseWindow, at: now) {
            return lastFetched
        }
        let task = Task<TokenSnapshot?, Never> {
            await Self.fetch(connections: connections)
        }
        inFlight = task
        let result = await task.value
        // Only the creator clears it: joiners return above and a new task can
        // start only after this line.
        inFlight = nil
        if let result { lastFetched = result }
        return result
    }

    private static func fetch(connections: HubConnectionStore) async -> TokenSnapshot? {
        do {
            // Throws before first unlock (Keychain unreadable): never call the
            // Hub without its secret — the cache is the right answer then.
            let client = try HubClient(store: connections, session: WidgetNetwork.session, timeout: HubClient.widgetTimeout)
            let snapshot = try await makeSnapshot(client: client)
            try? SnapshotStore.shared.save(snapshot)
            return snapshot
        } catch {
            return nil
        }
    }

    /// Its own function so the decoded `HubStats` (the whole response) is
    /// released as soon as the compact snapshot exists.
    private static func makeSnapshot(client: HubClient) async throws -> TokenSnapshot {
        let stats = try await client.stats()
        return TokenSnapshot(stats: stats, fetchedAt: Date())
    }
}

enum WidgetNetwork {
    /// Ephemeral and cache-less: usage data never lands in a URL cache, and
    /// the response is not kept in memory after decoding.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // The request timeout is an idle timeout; this caps the whole transfer
        // so a slow trickle cannot outlast the time WidgetKit gives a provider.
        configuration.timeoutIntervalForResource = HubClient.widgetTimeout + 5
        return URLSession(configuration: configuration)
    }()
}
