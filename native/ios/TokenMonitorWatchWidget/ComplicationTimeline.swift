import Foundation
import TokenMonitorKit
import WidgetKit

/// Complication kinds. Watch faces store these, so renaming one removes the
/// user's complication.
enum ComplicationKind {
    static let usage = "com.tokenmonitor.watch.usage"
    static let quota = "com.tokenmonitor.watch.quota"
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenSnapshot?
    let isConfigured: Bool
}

/// Reads the watch-side cache. The iPhone's WatchConnectivity push (stored by
/// the watch app) is the main source; the extension calls the Hub itself only
/// when the cache is old, best effort and once for both complications
/// (`ComplicationLoader.coalescer`), because a watch widget extension has
/// little memory and only seconds to run.
struct ComplicationProvider: TimelineProvider {
    /// A cache older than this is worth one Hub request.
    static let refreshAge: TimeInterval = 20 * 60
    static let reloadInterval: TimeInterval = 20 * 60
    static let unconfiguredReloadInterval: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> ComplicationEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let entry = ComplicationLoader.cachedEntry()
        // The face gallery should show what the complication looks like, not
        // an empty state, before the iPhone has sent anything.
        if context.isPreview, entry.snapshot == nil {
            completion(.sample)
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            let entry = await ComplicationLoader.freshEntry()
            let interval = entry.isConfigured ? Self.reloadInterval : Self.unconfiguredReloadInterval
            let reload = entry.date.addingTimeInterval(interval)
            var entries = [entry]
            // At midnight the cached "today" stops being today's: re-render
            // then so the face does not show yesterday's total as today's.
            let calendar = Calendar.current
            if entry.snapshot != nil,
               let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date)),
               midnight < reload {
                entries.append(ComplicationEntry(date: midnight, snapshot: entry.snapshot, isConfigured: entry.isConfigured))
            }
            completion(Timeline(entries: entries, policy: .after(reload)))
        }
    }
}

enum ComplicationLoader {
    /// Both complications ask for their timelines together; they share one
    /// Hub fetch, and one that just finished is reused for this long.
    static let coalescer = SnapshotFetchCoalescer(reuseWindow: 60)

    static func cachedEntry(at date: Date = Date()) -> ComplicationEntry {
        guard let hubKey = HubConnectionStore.shared.snapshotKey else {
            return ComplicationEntry(date: date, snapshot: nil, isConfigured: false)
        }
        return ComplicationEntry(date: date, snapshot: cachedSnapshot(hubKey: hubKey), isConfigured: true)
    }

    /// The watch-side snapshot, unless it came from another Hub than the
    /// saved one.
    static func cachedSnapshot(hubKey: String) -> TokenSnapshot? {
        guard let snapshot = SnapshotStore.shared.load(), snapshot.belongs(toHubKey: hubKey) else { return nil }
        return snapshot
    }

    /// The cache, refreshed from the Hub first when it is older than
    /// `ComplicationProvider.refreshAge`; any failure falls back to the cache.
    static func freshEntry(at date: Date = Date()) async -> ComplicationEntry {
        let connections = HubConnectionStore.shared
        guard let hubKey = connections.snapshotKey else {
            return ComplicationEntry(date: date, snapshot: nil, isConfigured: false)
        }
        let cached = cachedSnapshot(hubKey: hubKey)
        if let cached, !cached.isOlder(than: ComplicationProvider.refreshAge, at: date) {
            return ComplicationEntry(date: date, snapshot: cached, isConfigured: true)
        }
        let fetched = await coalescer.snapshot(hubKey: hubKey, now: date) {
            await fetch(connections: connections, hubKey: hubKey)
        }
        return ComplicationEntry(date: date, snapshot: fetched ?? cached, isConfigured: true)
    }

    private static func fetch(connections: HubConnectionStore, hubKey: String) async -> TokenSnapshot? {
        do {
            // Throws while the Keychain is locked: never call the Hub without
            // its secret.
            let client = try HubClient(store: connections, session: ComplicationNetwork.session, timeout: HubClient.widgetTimeout)
            // The iPhone switched the Hub since the caller read the settings.
            guard client.connection.snapshotKey == hubKey else { return nil }
            let fresh = try await makeSnapshot(client: client)
            // Switched while the request was in flight: these numbers are the
            // previous Hub's and must not overwrite the new Hub's cache.
            guard !Task.isCancelled, connections.snapshotKey == hubKey else { return nil }
            // The watch app or the iPhone may have stored a newer one meanwhile.
            if let latest = cachedSnapshot(hubKey: hubKey), latest.fetchedAt >= fresh.fetchedAt {
                return latest
            }
            try? SnapshotStore.shared.save(fresh)
            return fresh
        } catch {
            return nil
        }
    }

    /// Its own function so the decoded `HubStats` (the whole, possibly
    /// multi-megabyte response) is released as soon as the compact snapshot
    /// exists.
    private static func makeSnapshot(client: HubClient) async throws -> TokenSnapshot {
        let stats = try await client.stats()
        return TokenSnapshot(stats: stats, fetchedAt: Date(), hub: client.connection)
    }
}

enum ComplicationNetwork {
    /// Ephemeral and cache-less: usage data never lands in a URL cache, and
    /// the response is not kept in memory after decoding.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // The request timeout is an idle timeout; this caps the whole transfer
        // so a slow trickle cannot outlast the seconds a complication gets.
        configuration.timeoutIntervalForResource = HubClient.widgetTimeout + 5
        return URLSession(configuration: configuration)
    }()
}
