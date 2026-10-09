import Foundation
import Observation
import TokenMonitorKit

/// The watch app's data: the cached snapshot first, then the Hub's own
/// numbers, fetched once a minute while the app is in the foreground.
///
/// No SSE stream on the watch: a held connection costs more battery than a
/// once-a-minute poll while the screen is on, and nothing runs in between.
@Observable
final class WatchStore {
    static let refreshInterval: TimeInterval = 60
    /// A snapshot younger than this is not refetched when the app becomes
    /// active again (raising the wrist twice should not cost two requests).
    static let minimumRefreshAge: TimeInterval = 30
    /// Older than this, the UI marks the numbers as possibly stale.
    static let staleAge: TimeInterval = 15 * 60

    /// The saved Hub URL (no Keychain read, so it is known even while the
    /// Keychain is locked).
    private(set) var hubURL: URL? = nil
    private(set) var snapshot: TokenSnapshot? = nil
    private(set) var isRefreshing = false
    /// The last refresh failed; cleared by the next success.
    private(set) var lastError: HubClientError? = nil

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var observer: NSObjectProtocol? = nil

    init() {
        hubURL = HubConnectionStore.shared.baseURL
        snapshot = Self.storedSnapshot(for: hubURL)
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

    func isStale(at date: Date = Date()) -> Bool {
        guard let snapshot else { return false }
        return snapshot.isSourceStale || snapshot.isOlder(than: Self.staleAge, at: date)
    }

    /// Refreshes now and then every `refreshInterval` until the calling task
    /// is cancelled (the scene leaving `.active`).
    @MainActor
    func runWhileActive() async {
        isActive = true
        defer { isActive = false }
        reloadFromStores()
        if !isConfigured {
            WatchSessionBridge.shared.requestSync()
        }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
        }
    }

    /// Fetches the Hub. Without `force`, skips while a refresh runs or the
    /// snapshot is younger than `minimumRefreshAge`.
    @MainActor
    func refresh(force: Bool = false) async {
        guard let url = HubConnectionStore.shared.baseURL else {
            hubURL = nil
            return
        }
        if !force {
            if isRefreshing { return }
            if let snapshot, !snapshot.isOlder(than: Self.minimumRefreshAge) { return }
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
        do {
            let stats = try await HubClient(connection: connection).stats()
            // A newer refresh started, or the iPhone switched Hubs meanwhile.
            guard current == generation, HubConnectionStore.shared.baseURL == url else { return }
            let fresh = TokenSnapshot(stats: stats, hub: connection)
            snapshot = fresh
            lastError = nil
            try? SnapshotStore.shared.save(fresh)
            WatchSessionBridge.shared.reloadComplications()
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

    /// Picks up what the WatchConnectivity bridge stored.
    @MainActor
    func reloadFromStores() {
        let url = HubConnectionStore.shared.baseURL
        let hubChanged = url != hubURL
        hubURL = url
        let stored = Self.storedSnapshot(for: url)
        if hubChanged {
            generation += 1
            isRefreshing = false
            snapshot = stored
            lastError = nil
            if url != nil, isActive {
                Task { @MainActor in
                    await self.refresh(force: true)
                }
            }
        } else if let stored, stored.fetchedAt > (snapshot?.fetchedAt ?? .distantPast) {
            snapshot = stored
        }
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
