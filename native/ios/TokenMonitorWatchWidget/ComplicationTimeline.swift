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
    /// The display preferences the iPhone sent (units, currency,
    /// used/remaining, hidden providers) with the cached exchange rates.
    var context: PresentationContext = .standard

    /// The user's `complicationRefreshMinutes` timings.
    var timing: ComplicationRefreshTiming {
        RefreshPolicy.complication(context.preferences.complicationRefreshMinutes)
    }
}

/// Reads the watch-side cache. The iPhone's WatchConnectivity push (stored by
/// the watch app) is the main source; the extension calls the Hub itself only
/// when the cache is older than the user's complication interval or was built
/// for other settings, best effort and once for both complications
/// (`ComplicationLoader.coalescer`), because a watch widget extension has
/// little memory and only seconds to run.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let entry = ComplicationLoader.cachedEntry()
        // The face gallery should show what the complication looks like, not
        // an empty state, before the iPhone has sent anything.
        if context.isPreview, entry.snapshot == nil {
            completion(.sample(context: entry.context))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            let entry = await ComplicationLoader.freshEntry()
            let timing = entry.timing
            let interval = entry.isConfigured ? timing.reloadInterval : timing.unconfiguredReloadInterval
            let reload = entry.date.addingTimeInterval(interval)
            var entries = [entry]
            // At midnight the cached "today" stops being today's: re-render
            // then so the face does not show yesterday's total as today's.
            let calendar = Calendar.current
            if entry.snapshot != nil,
               let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date)),
               midnight < reload {
                entries.append(ComplicationEntry(date: midnight, snapshot: entry.snapshot, isConfigured: entry.isConfigured, context: entry.context))
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
        let context = PresentationContext.load()
        guard let hubKey = HubConnectionStore.shared.snapshotKey else {
            return ComplicationEntry(date: date, snapshot: nil, isConfigured: false, context: context)
        }
        return ComplicationEntry(date: date, snapshot: cachedSnapshot(hubKey: hubKey), isConfigured: true, context: context)
    }

    /// The watch-side snapshot, unless it came from another Hub than the
    /// saved one.
    static func cachedSnapshot(hubKey: String) -> TokenSnapshot? {
        guard let snapshot = SnapshotStore.shared.load(), snapshot.belongs(toHubKey: hubKey) else { return nil }
        return snapshot
    }

    /// The cache, refreshed from the Hub first when it is older than the
    /// user's complication interval or was built for other settings (another
    /// scope, tool or Limits lists, aliases); any failure falls back to the
    /// cache.
    static func freshEntry(at date: Date = Date()) async -> ComplicationEntry {
        let context = PresentationContext.load()
        let connections = HubConnectionStore.shared
        guard let hubKey = connections.snapshotKey else {
            return ComplicationEntry(date: date, snapshot: nil, isConfigured: false, context: context)
        }
        let timing = RefreshPolicy.complication(context.preferences.complicationRefreshMinutes)
        let builder = makeBuilder(preferences: context.preferences, hubKey: hubKey)
        let cached = cachedSnapshot(hubKey: hubKey)
        if let cached, builder.isCurrent(cached, hubKey: hubKey), !cached.isOlder(than: timing.refreshAge, at: date) {
            return ComplicationEntry(date: date, snapshot: cached, isConfigured: true, context: context)
        }
        var fetched = await coalescer.snapshot(hubKey: hubKey, now: date) {
            await fetch(connections: connections, hubKey: hubKey, builder: builder)
        }
        if let snapshot = fetched {
            // The coalescer keys by Hub only, so a fetch made moments ago for
            // the settings before a change can come back: ask once more. The
            // fetch may have brought a new alias document, so compare with
            // the cache as it is now.
            let current = makeBuilder(preferences: context.preferences, hubKey: hubKey)
            if !current.isCurrent(snapshot, hubKey: hubKey) {
                fetched = await coalescer.snapshot(hubKey: hubKey, force: true, now: date) {
                    await fetch(connections: connections, hubKey: hubKey, builder: current)
                } ?? snapshot
            }
        }
        return ComplicationEntry(date: date, snapshot: fetched ?? cached, isConfigured: true, context: context)
    }

    /// The stored preferences with the Hub's cached alias document.
    private static func makeBuilder(preferences: DisplayPreferences, hubKey: String) -> SnapshotBuilder {
        SnapshotBuilder(preferences: preferences, aliases: ModelAliasCache.shared.load(hubKey: hubKey))
    }

    private static func fetch(connections: HubConnectionStore, hubKey: String, builder: SnapshotBuilder) async -> TokenSnapshot? {
        do {
            // Throws while the Keychain is locked: never call the Hub without
            // its secret.
            let client = try HubClient(store: connections, session: ComplicationNetwork.session, timeout: HubClient.widgetTimeout)
            // The iPhone switched the Hub since the caller read the settings.
            guard client.connection.snapshotKey == hubKey else { return nil }
            let fresh = try await makeSnapshot(client: client, builder: builder)
            // Switched while the request was in flight: these numbers are the
            // previous Hub's and must not overwrite the new Hub's cache.
            guard !Task.isCancelled, connections.snapshotKey == hubKey else { return nil }
            // The watch app or the iPhone may have stored a newer one, built
            // the same way, meanwhile.
            if let latest = cachedSnapshot(hubKey: hubKey), latest.fetchedAt >= fresh.fetchedAt,
               latest.projectionKey == fresh.projectionKey {
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
    /// exists. Decodes the scoped device's details only, refreshes the alias
    /// document when the Hub advertises another revision, and builds through
    /// `SnapshotBuilder` like every other surface.
    private static func makeSnapshot(client: HubClient, builder: SnapshotBuilder) async throws -> TokenSnapshot {
        var builder = builder
        let stats = try await client.stats(options: .compact(scopedTo: builder.preferences.deviceScope))
        builder.aliases = await SharedSettingsRefresher.modelAliases(stats: stats, client: client, hubKey: client.connection.snapshotKey)
        return builder.snapshot(from: stats, fetchedAt: Date(), hub: client.connection)
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
