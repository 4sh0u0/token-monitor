import Foundation
import Observation
import TokenMonitorKit

/// The watch app's data: the cached snapshot first, then the Hub's own
/// numbers, fetched at the user's watch refresh interval
/// (`watchRefreshSeconds`) while the app is in the foreground.
///
/// No SSE stream on the watch: a held connection costs more battery than a
/// poll while the screen is on, and nothing runs in between.
///
/// Every snapshot is built through `SnapshotBuilder` from the display
/// preferences the iPhone sent (`WatchSessionBridge`, key `prefs`) and the
/// Hub's cached model aliases, so the watch shows the same scope, tool order
/// and visible Limits items as the phone, its widgets and the complications.
@Observable
final class WatchStore {
    /// The saved Hub URL (no Keychain read, so it is known even while the
    /// Keychain is locked).
    private(set) var hubURL: URL? = nil
    private(set) var snapshot: TokenSnapshot? = nil
    private(set) var isRefreshing = false
    /// The last refresh failed; cleared by the next success.
    private(set) var lastError: HubClientError? = nil
    /// Preferences, exchange rates and UI language every page formats with
    /// (`.tmPresentation` at the root).
    private(set) var context: PresentationContext

    /// The stored preferences and the Hub's alias document; its
    /// `projectionKey` says whether a snapshot was built for them.
    @ObservationIgnored private var builder: SnapshotBuilder
    /// The last stats fetched, kept so a settings change from the iPhone
    /// (another tool order, hidden Limits items, the scope back to all
    /// devices) rebuilds the snapshot at once instead of waiting for the Hub.
    @ObservationIgnored private var lastFetch: FetchedStats? = nil
    @ObservationIgnored private var generation = 0
    /// Polling loops running; more than one only for a moment while SwiftUI
    /// replaces the loop after the interval changed.
    @ObservationIgnored private var activeLoops = 0
    @ObservationIgnored private var observer: NSObjectProtocol? = nil

    init() {
        let url = HubConnectionStore.shared.baseURL
        hubURL = url
        context = PresentationContext.load()
        builder = SnapshotBuilder.load(hubKey: url.map(HubConnection.snapshotKey(for:)))
        snapshot = Self.storedSnapshot(for: url)
        observer = NotificationCenter.default.addObserver(
            forName: WatchSessionBridge.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromStores()
            }
        }
    }

    var isConfigured: Bool { hubURL != nil }

    /// `host[:port]` of the Hub, for the status page.
    var hubHost: String? {
        hubURL.map { HubConnection(baseURL: $0, secret: "").displayHost }
    }

    /// Poll interval, re-activation threshold and stale age for the user's
    /// `watchRefreshSeconds` choice.
    var timing: WatchRefreshTiming {
        RefreshPolicy.watch(context.preferences.watchRefreshSeconds)
    }

    func isStale(at date: Date = Date()) -> Bool {
        guard let snapshot else { return false }
        return snapshot.isSourceStale || snapshot.isOlder(than: timing.staleAge, at: date)
    }

    private var isActive: Bool { activeLoops > 0 }

    /// Refreshes now and then every `timing.pollInterval` until the calling
    /// task is cancelled (the scene leaving `.active`, or a new interval).
    @MainActor
    func runWhileActive() async {
        activeLoops += 1
        defer { activeLoops -= 1 }
        reloadFromStores()
        if !isConfigured {
            WatchSessionBridge.shared.requestSync()
        }
        while !Task.isCancelled {
            await refresh()
            let interval = max(1, timing.pollInterval)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Fetches the Hub. Without `force`, skips while a refresh runs or while
    /// the snapshot is younger than `timing.minimumRefreshAge` and was built
    /// for the current settings.
    @MainActor
    func refresh(force: Bool = false) async {
        guard let url = HubConnectionStore.shared.baseURL else {
            hubURL = nil
            return
        }
        let hubKey = HubConnection.snapshotKey(for: url)
        if !force {
            if isRefreshing { return }
            if let snapshot, builder.isCurrent(snapshot, hubKey: hubKey),
               !snapshot.isOlder(than: timing.minimumRefreshAge) {
                return
            }
        }
        let connection: HubConnection
        do {
            guard let loaded = try HubConnectionStore.shared.loadConnection() else { return }
            connection = loaded
        } catch {
            // Keychain locked: calling the Hub without its secret would only
            // produce a misleading "unauthorized"; keep showing the cache.
            return
        }
        generation += 1
        let current = generation
        isRefreshing = true
        defer {
            if current == generation { isRefreshing = false }
        }
        // Only the scoped device's details: the watch shows one scope.
        let options = HubDecodingOptions.compact(scopedTo: builder.preferences.deviceScope)
        do {
            let client = HubClient(connection: connection)
            let stats = try await client.stats(options: options)
            // A newer refresh started, or the iPhone switched Hubs meanwhile.
            guard current == generation, HubConnectionStore.shared.baseURL == url else { return }
            // Fetched only when the Hub advertises another revision.
            let aliases = await SharedSettingsRefresher.modelAliases(stats: stats, client: client, hubKey: hubKey)
            guard current == generation, HubConnectionStore.shared.baseURL == url else { return }
            builder.aliases = aliases
            let fetched = FetchedStats(stats: stats, options: options, hubKey: hubKey, baseURL: url, fetchedAt: Date())
            lastFetch = fetched
            lastError = nil
            // Nil when the scope moved to a device this decode left out; the
            // settings change already asked for another refresh.
            if let fresh = makeSnapshot(from: fetched) {
                adopt(fresh)
            }
        } catch is CancellationError {
            return
        } catch let error as HubClientError {
            guard current == generation else { return }
            lastError = error
            if error == .unauthorized {
                // The secret may have changed on the iPhone.
                WatchSessionBridge.shared.requestSync()
            }
        } catch {
            guard current == generation else { return }
            lastError = .transport(error.localizedDescription)
        }
    }

    /// The scene left the foreground: let the complications catch up with
    /// what the app last showed.
    @MainActor
    func didLeaveForeground() {
        WatchSessionBridge.shared.flushComplicationReload()
    }

    /// Picks up what the WatchConnectivity bridge stored: the connection, a
    /// newer snapshot, and the display preferences and rates.
    @MainActor
    func reloadFromStores() {
        let url = HubConnectionStore.shared.baseURL
        let hubChanged = url != hubURL
        hubURL = url
        let hubKey = url.map(HubConnection.snapshotKey(for:))

        let loaded = PresentationContext.load()
        if loaded != context {
            context = loaded
        }
        let previousProjection = builder.projectionKey
        builder = SnapshotBuilder.load(hubKey: hubKey)

        let stored = Self.storedSnapshot(for: url)
        if hubChanged {
            generation += 1
            isRefreshing = false
            snapshot = stored
            lastError = nil
            lastFetch = nil
            if url != nil, isActive {
                Task { @MainActor in
                    await self.refresh(force: true)
                }
            }
            return
        }
        if let stored, builder.prefers(stored, over: snapshot, hubKey: hubKey) {
            snapshot = stored
        }
        guard builder.projectionKey != previousProjection else { return }
        // The scope, the tool lists, the Limits order or hidden items, or the
        // alias document changed. The iPhone usually sends a snapshot built
        // for the new settings along with them; otherwise rebuild from the
        // last stats when they cover the new scope, else ask the Hub.
        if let snapshot, builder.isCurrent(snapshot, hubKey: hubKey) { return }
        if let lastFetch, lastFetch.hubKey == hubKey, let rebuilt = makeSnapshot(from: lastFetch) {
            adopt(rebuilt)
        } else if url != nil, isActive {
            Task { @MainActor in
                await self.refresh(force: true)
            }
        }
    }

    // MARK: Building

    /// What one Hub fetch decoded, and how.
    private struct FetchedStats {
        let stats: HubStats
        let options: HubDecodingOptions
        let hubKey: String
        let baseURL: URL
        let fetchedAt: Date
    }

    /// The snapshot of `fetched` for the current settings; nil when the
    /// scoped device's details were not part of that decode.
    @MainActor
    private func makeSnapshot(from fetched: FetchedStats) -> TokenSnapshot? {
        if let deviceID = builder.preferences.deviceScope.deviceID,
           !fetched.options.deviceDetail.includes(deviceID) {
            return nil
        }
        // The secret is not needed to stamp the Hub key.
        let hub = HubConnection(baseURL: fetched.baseURL, secret: "")
        return builder.snapshot(from: fetched.stats, fetchedAt: fetched.fetchedAt, hub: hub)
    }

    /// Shows `fresh` and shares it with the complications.
    @MainActor
    private func adopt(_ fresh: TokenSnapshot) {
        snapshot = fresh
        try? SnapshotStore.shared.save(fresh)
        WatchSessionBridge.shared.reloadComplications()
    }

    /// The cached snapshot, when it was read from the Hub at `url`: one
    /// written for the previous Hub (a complication fetch that crossed a
    /// switch) must not be shown as this one's.
    private static func storedSnapshot(for url: URL?) -> TokenSnapshot? {
        guard let url, let snapshot = SnapshotStore.shared.load(),
              snapshot.belongs(toHubKey: HubConnection.snapshotKey(for: url)) else { return nil }
        return snapshot
    }
}

extension SnapshotBuilder {
    /// Whether `incoming` should replace `current`: it is newer, and it does
    /// not trade a snapshot built for these settings (`isCurrent`) for one
    /// built for others — a pushed iPhone snapshot folded with an older
    /// alias revision, say. With nothing current, anything belongs.
    func prefers(_ incoming: TokenSnapshot, over current: TokenSnapshot?, hubKey: String?) -> Bool {
        guard let current else { return true }
        guard incoming.fetchedAt > current.fetchedAt else { return false }
        return isCurrent(incoming, hubKey: hubKey) || !isCurrent(current, hubKey: hubKey)
    }
}
