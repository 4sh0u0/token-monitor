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
        guard let hubKey = connections.snapshotKey else { return .notConfigured }
        let cached = cachedSnapshot(hubKey: hubKey)
        if !forceRefresh, let cached, isFresh(cached, at: now) {
            return .ready(cached)
        }
        if let fetched = await SnapshotRefresher.refresh(connections: connections, hubKey: hubKey, force: forceRefresh, now: now) {
            return .ready(fetched)
        }
        if let cached { return .ready(cached) }
        return .unavailable
    }

    /// The App Group snapshot, unless it came from another Hub than the saved
    /// one (the app clears it on a Hub switch, but a widget can read it first,
    /// or a fetch for the old Hub can land after the clear).
    static func cachedSnapshot(hubKey: String? = HubConnectionStore.shared.snapshotKey) -> TokenSnapshot? {
        guard let snapshot = SnapshotStore.shared.load(), snapshot.belongs(toHubKey: hubKey) else { return nil }
        return snapshot
    }

    /// A snapshot dated in the future (the clock moved back) counts as old,
    /// otherwise it would never be refreshed.
    static func isFresh(_ snapshot: TokenSnapshot, at now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= -60 && age <= WidgetTiming.refreshAfter
    }
}

/// Hub fetches of the extension process, shared through one
/// `SnapshotFetchCoalescer`: `reloadAllTimelines()` asks for every placed
/// widget's timeline at once, and each decoding its own copy of the full
/// `/api/stats` response is how a widget extension blows through its memory
/// limit.
enum SnapshotRefresher {
    private static let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)

    static func refresh(connections: HubConnectionStore, hubKey: String, force: Bool, now: Date) async -> TokenSnapshot? {
        await coalescer.snapshot(hubKey: hubKey, force: force, now: now) {
            await fetch(connections: connections, hubKey: hubKey)
        }
    }

    private static func fetch(connections: HubConnectionStore, hubKey: String) async -> TokenSnapshot? {
        do {
            // Throws before first unlock (Keychain unreadable): never call the
            // Hub without its secret — the cache is the right answer then.
            let client = try HubClient(store: connections, session: WidgetNetwork.session, timeout: HubClient.widgetTimeout)
            // The Hub was switched since the caller read the settings.
            guard client.connection.snapshotKey == hubKey else { return nil }
            let snapshot = try await makeSnapshot(client: client)
            // Switched while the request was in flight: these numbers are the
            // previous Hub's and must not overwrite the new Hub's cache.
            guard !Task.isCancelled, connections.snapshotKey == hubKey else { return nil }
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
        return TokenSnapshot(stats: stats, fetchedAt: Date(), hub: client.connection)
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
