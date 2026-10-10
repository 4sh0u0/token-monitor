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
/// Hub when it is missing, old, or was built for other settings (device
/// scope, model aliases, tool and Limits preferences — its `projectionKey`).
/// Never throws and never waits longer than the widget network timeout; any
/// failure falls back to the cache, even one built for other settings.
enum SnapshotLoader {
    static func load(forceRefresh: Bool, context: PresentationContext, now: Date = Date()) async -> WidgetDataState {
        let connections = HubConnectionStore.shared
        // Only the URL is read here; the Keychain is touched just before a fetch.
        guard let hubKey = connections.snapshotKey else { return .notConfigured }
        let builder = SnapshotBuilder.load(hubKey: hubKey)
        let cached = cachedSnapshot(hubKey: hubKey)
        if !forceRefresh, let cached, isFresh(cached, builder: builder, hubKey: hubKey, timing: context.widgetTiming, at: now) {
            return .ready(cached)
        }
        if let fetched = await SnapshotRefresher.refresh(connections: connections, hubKey: hubKey, builder: builder, force: forceRefresh, now: now) {
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

    /// Fresh enough to show without asking the Hub: built for the current
    /// settings (`SnapshotBuilder.isCurrent`), younger than `refreshAfter`,
    /// and fetched today (after midnight a cached "today" is yesterday's). A
    /// snapshot dated in the future (the clock moved back) counts as old,
    /// otherwise it would never be refreshed.
    static func isFresh(_ snapshot: TokenSnapshot, builder: SnapshotBuilder, hubKey: String, timing: WidgetRefreshTiming, at now: Date) -> Bool {
        guard builder.isCurrent(snapshot, hubKey: hubKey), snapshot.isCurrent(.today, at: now) else { return false }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= -60 && age <= timing.refreshAfter
    }
}

/// Hub fetches of the extension process, shared through one
/// `SnapshotFetchCoalescer`: `reloadAllTimelines()` asks for every placed
/// widget's timeline at once, and each decoding its own copy of the
/// `/api/stats` response is how a widget extension blows through its memory
/// limit.
enum SnapshotRefresher {
    private static let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)

    /// The coalescer is keyed by Hub only (it hands out only results that
    /// `belong(toHubKey:)` its key), so a fetch made moments ago for the
    /// settings before a change can come back. Such a result is not current
    /// for the settings as they are now (`SnapshotBuilder.isCurrent`, read
    /// again: the app may have saved a new alias document meanwhile), so the
    /// Hub is asked once more, bypassing the reuse window; if that fails the
    /// first result is still better than the cache.
    static func refresh(
        connections: HubConnectionStore,
        hubKey: String,
        builder: SnapshotBuilder,
        force: Bool,
        now: Date
    ) async -> TokenSnapshot? {
        let fetched = await coalescer.snapshot(hubKey: hubKey, force: force, now: now) {
            await fetch(connections: connections, hubKey: hubKey, builder: builder)
        }
        guard let fetched else { return nil }
        let current = SnapshotBuilder.load(hubKey: hubKey)
        guard !current.isCurrent(fetched, hubKey: hubKey) else { return fetched }
        let refetched = await coalescer.snapshot(hubKey: hubKey, force: true, now: now) {
            await fetch(connections: connections, hubKey: hubKey, builder: current)
        }
        return refetched ?? fetched
    }

    /// Reads the Hub, builds the snapshot for `builder`'s settings and saves
    /// it to the App Group.
    private static func fetch(connections: HubConnectionStore, hubKey: String, builder: SnapshotBuilder) async -> TokenSnapshot? {
        do {
            // Throws before first unlock (Keychain unreadable): never call the
            // Hub without its secret — the cache is the right answer then.
            let client = try HubClient(store: connections, session: WidgetNetwork.session, timeout: HubClient.widgetTimeout)
            // The Hub was switched since the caller read the settings.
            guard client.connection.snapshotKey == hubKey else { return nil }
            let snapshot = try await makeSnapshot(client: client, builder: builder)
            // Switched while the request was in flight: these numbers are the
            // previous Hub's and must not overwrite the new Hub's cache.
            guard !Task.isCancelled, connections.snapshotKey == hubKey else { return nil }
            try? SnapshotStore.shared.save(snapshot)
            return snapshot
        } catch {
            return nil
        }
    }

    /// Its own function so the decoded `HubStats` is released as soon as the
    /// compact snapshot exists. Only the scoped device's details are decoded
    /// (`.compact(scopedTo:)`), never sessions or projects.
    private static func makeSnapshot(client: HubClient, builder: SnapshotBuilder) async throws -> TokenSnapshot {
        let stats = try await client.stats(options: .compact(scopedTo: builder.preferences.deviceScope))
        return builder.snapshot(from: stats, fetchedAt: Date(), hub: client.connection)
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
