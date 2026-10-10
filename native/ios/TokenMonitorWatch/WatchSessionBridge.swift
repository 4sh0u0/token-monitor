import Foundation
import TokenMonitorKit
import WatchConnectivity
import WidgetKit

/// Receives the Hub connection, snapshots and display preferences from the
/// iPhone (`PhoneSessionBridge` in the iOS app target) and stores them in the
/// watch's own Keychain item and App Group, where the complications read them.
///
/// Payload keys mirror `PhoneSessionBridge.Key`; change both together.
final class WatchSessionBridge: NSObject, @unchecked Sendable {
    // @unchecked: every mutable property below is confined to `queue`.

    static let shared = WatchSessionBridge()

    /// Posted on the main queue after the stored connection, snapshot or
    /// display preferences changed.
    static let didChangeNotification = Notification.Name("TokenMonitorWatchDataDidChange")

    private enum Key {
        static let version = "v"
        static let revision = "rev"
        static let connected = "connected"
        static let hub = "hub"
        static let snapshot = "snapshot"
        static let request = "request"
        static let syncRequest = "sync"
        /// `PreferencesPayload` JSON (`PhoneSessionBridge.Key.prefs`): the
        /// iPhone's display preferences and exchange-rate cache. It rides in
        /// the application context and the sync reply, never in a
        /// complication transfer; an older iPhone never sends it, and the
        /// watch then keeps the defaults.
        static let prefs = PreferencesPayload.contextKey
    }

    private static let protocolVersion = 1
    /// The revision of the connection state last applied, in the App Group so
    /// it survives relaunches.
    private static let appliedRevisionKey = "watchSync.appliedRevision"
    /// Complication reloads count against a daily WidgetKit budget; routine
    /// snapshot updates are spaced out, connection changes never wait.
    private static let complicationReloadInterval: TimeInterval = 5 * 60
    private static let syncRequestInterval: TimeInterval = 30

    private let queue = DispatchQueue(label: "TokenMonitor.WatchSessionBridge", qos: .utility)
    private var lastSyncRequestAt: Date?
    private var lastComplicationReloadAt: Date?
    private var hasPendingComplicationReload = false

    private override init() {
        super.init()
    }

    /// Call once at launch (the App's `init`), before any background task
    /// waits on the session.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Asks the iPhone for its connection — when the watch has none yet, or
    /// the Hub rejected the secret it has. Messages wake the iOS app in the
    /// background, so this works whenever the phone is reachable.
    func requestSync(force: Bool = false) {
        queue.async { [self] in
            sendSyncRequest(force: force)
        }
    }

    /// Reloads the complications; routine updates are throttled and the
    /// skipped one runs on the next call or `flushComplicationReload()`.
    func reloadComplications(force: Bool = false) {
        queue.async { [self] in
            reloadComplicationsLocked(force: force)
        }
    }

    /// Runs a reload a throttle skipped, e.g. when the app leaves the
    /// foreground so the watch face shows what the app just showed.
    func flushComplicationReload() {
        queue.async { [self] in
            if hasPendingComplicationReload {
                reloadComplicationsLocked(force: true)
            }
        }
    }

    /// Keeps a background launch alive until WatchConnectivity has handed
    /// over what it woke the app for, and it has been stored.
    func finishPendingDeliveries() async {
        activate()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        for _ in 0..<40 {
            if session.activationState == .activated, !session.hasContentPending { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
        // `apply` reloads the complications from the main actor; let that
        // run before the system suspends the app again.
        await MainActor.run {}
    }

    // MARK: On `queue`

    private func sendSyncRequest(force: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        if !force, let lastSyncRequestAt, Date().timeIntervalSince(lastSyncRequestAt) < Self.syncRequestInterval {
            return
        }
        lastSyncRequestAt = Date()
        session.sendMessage([Key.request: Key.syncRequest], replyHandler: { [self] reply in
            queue.async {
                self.apply(reply, carriesConnection: true)
            }
        }, errorHandler: nil)
    }

    private func reloadComplicationsLocked(force: Bool) {
        if !force, let lastComplicationReloadAt,
           Date().timeIntervalSince(lastComplicationReloadAt) < Self.complicationReloadInterval {
            hasPendingComplicationReload = true
            return
        }
        lastComplicationReloadAt = Date()
        hasPendingComplicationReload = false
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Applies a context, a complication transfer or a sync reply.
    /// - Parameter carriesConnection: complication transfers carry only a
    ///   snapshot.
    private func apply(_ payload: [String: Any], carriesConnection: Bool) {
        guard (payload[Key.version] as? NSNumber)?.intValue == Self.protocolVersion else { return }
        let revision = (payload[Key.revision] as? NSNumber)?.int64Value ?? 0
        let defaults = AppGroup.defaults
        let appliedRevision = (defaults.object(forKey: Self.appliedRevisionKey) as? NSNumber)?.int64Value ?? 0
        // Older than the connection state already applied: e.g. a snapshot
        // queued before the user disconnected, delivered after (or a sync
        // reply carrying the preferences the user has since changed).
        guard revision >= appliedRevision else { return }

        // First, so a locked Keychain (below) does not hold them back, and so
        // the snapshot check below already sees them.
        let preferencesChanged = carriesConnection && applyPreferences(payload[Key.prefs] as? Data)
        var connectionChanged = false
        var snapshotChanged = false
        defer {
            announce(
                connectionChanged: connectionChanged,
                snapshotChanged: snapshotChanged,
                preferencesChanged: preferencesChanged,
                carriesConnection: carriesConnection
            )
        }

        let store = HubConnectionStore.shared
        let snapshots = SnapshotStore.shared

        if carriesConnection, let connected = payload[Key.connected] as? Bool {
            if connected {
                guard let data = payload[Key.hub] as? Data,
                      let connection = try? JSONDecoder().decode(HubConnection.self, from: data) else { return }
                let previousURL = store.baseURL
                if (try? store.loadConnection()) != connection {
                    do {
                        try store.save(connection)
                    } catch {
                        // Keychain not writable yet (before first unlock). The
                        // revision stays unapplied, so the retained
                        // `receivedApplicationContext` is applied again at the
                        // next activation.
                        return
                    }
                    if previousURL != connection.baseURL {
                        // The cached numbers belong to the previous Hub.
                        try? snapshots.clear()
                    }
                    connectionChanged = true
                }
            } else if store.isConfigured || FileManager.default.fileExists(atPath: snapshots.fileURL.path) {
                try? store.clear()
                try? snapshots.clear()
                connectionChanged = true
            }
            defaults.set(NSNumber(value: revision), forKey: Self.appliedRevisionKey)
        }

        // Only a snapshot of the Hub now saved: a complication transfer or a
        // sync reply can cross a Hub switch. Nil (no Hub) matches nothing.
        let hubKey = store.snapshotKey
        if let data = payload[Key.snapshot] as? Data,
           let snapshot = try? TokenSnapshot(jsonData: data),
           snapshot.schemaVersion <= TokenSnapshot.currentSchemaVersion,
           snapshot.belongs(toHubKey: hubKey) {
            // The watch fetches the Hub itself too; keep whichever is newer
            // (a cached one from another Hub never counts), but never trade
            // one built for this watch's settings for one built for others.
            let cached = snapshots.load().flatMap { $0.belongs(toHubKey: hubKey) ? $0 : nil }
            let builder = SnapshotBuilder.load(hubKey: hubKey)
            if builder.prefers(snapshot, over: cached, hubKey: hubKey) {
                try? snapshots.save(snapshot)
                snapshotChanged = true
            }
        }
    }

    /// Stores the iPhone's display preferences and exchange rates. Returns
    /// whether either changed. A payload without rates keeps the cached ones
    /// (the watch never fetches rates itself, so they came from the phone).
    private func applyPreferences(_ data: Data?) -> Bool {
        guard let data, let payload = PreferencesPayload.decode(data) else { return false }
        var changed = PreferencesStore.shared.save(payload.preferences)
        let rates = ExchangeRateStore.shared
        if let rateData = payload.rateCacheData, rateData != rates.data() {
            changed = rates.save(data: rateData) || changed
        }
        return changed
    }

    /// Tells the watch app what changed and brings the complications along.
    private func announce(connectionChanged: Bool, snapshotChanged: Bool, preferencesChanged: Bool, carriesConnection: Bool) {
        guard connectionChanged || snapshotChanged || preferencesChanged else { return }
        // `WatchStore` reloads its presentation, rebuilds or refetches the
        // snapshot for the new settings, and adopts a newer stored snapshot.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        // A complication transfer exists to update the face now; new
        // settings change what every complication shows (units, currency,
        // scope, hidden providers), so they never wait for the throttle.
        reloadComplicationsLocked(force: connectionChanged || preferencesChanged || !carriesConnection)
    }
}

extension WatchSessionBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        queue.async { [self] in
            if !context.isEmpty {
                apply(context, carriesConnection: true)
            }
            if !HubConnectionStore.shared.isConfigured {
                sendSyncRequest(force: true)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        queue.async { [self] in
            apply(applicationContext, carriesConnection: true)
        }
    }

    /// `transferCurrentComplicationUserInfo` on the iPhone lands here.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        queue.async { [self] in
            apply(userInfo, carriesConnection: false)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        queue.async { [self] in
            if !HubConnectionStore.shared.isConfigured {
                sendSyncRequest(force: false)
            }
        }
    }
}
