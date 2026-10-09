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
/// when the cache is old, best effort, because a watch widget extension has
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
    static func cachedEntry(at date: Date = Date()) -> ComplicationEntry {
        let isConfigured = HubConnectionStore.shared.isConfigured
        return ComplicationEntry(date: date, snapshot: isConfigured ? SnapshotStore.shared.load() : nil, isConfigured: isConfigured)
    }

    /// The cache, refreshed from the Hub first when it is older than
    /// `ComplicationProvider.refreshAge`; any failure falls back to the cache.
    static func freshEntry(at date: Date = Date()) async -> ComplicationEntry {
        let cached = cachedEntry(at: date)
        guard cached.isConfigured else { return cached }
        if let snapshot = cached.snapshot, !snapshot.isOlder(than: ComplicationProvider.refreshAge, at: date) {
            return cached
        }
        do {
            // Throws while the Keychain is locked: never call the Hub without
            // its secret.
            let client = try HubClient(store: HubConnectionStore.shared, timeout: HubClient.widgetTimeout)
            let fresh = TokenSnapshot(stats: try await client.stats())
            // The watch app or the iPhone may have stored a newer one meanwhile.
            if let latest = SnapshotStore.shared.load(), latest.fetchedAt >= fresh.fetchedAt {
                return ComplicationEntry(date: date, snapshot: latest, isConfigured: true)
            }
            try? SnapshotStore.shared.save(fresh)
            return ComplicationEntry(date: date, snapshot: fresh, isConfigured: true)
        } catch {
            return cached
        }
    }
}
