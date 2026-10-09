import Foundation
import TokenMonitorKit
import WatchConnectivity
import WidgetKit

/// Receives the Hub connection and snapshots from the iPhone
/// (`PhoneSessionBridge` in the iOS app target) and stores them in the watch's
/// own Keychain item and App Group, where the complications read them.
///
/// Payload keys mirror `PhoneSessionBridge.Key`; change both together.
final class WatchSessionBridge: NSObject, @unchecked Sendable {
    // @unchecked: every mutable property below is confined to `queue`.

    static let shared = WatchSessionBridge()

    /// Posted on the main queue after the stored connection or snapshot changed.
    static let didChangeNotification = Notification.Name("TokenMonitorWatchDataDidChange")

    private enum Key {
        static let version = "v"
        static let revision = "rev"
        static let connected = "connected"
        static let hub = "hub"
        static let snapshot = "snapshot"
        static let request = "request"
        static let syncRequest = "sync"
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
        // queued before the user disconnected, delivered after.
        guard revision >= appliedRevision else { return }

        let store = HubConnectionStore.shared
        let snapshots = SnapshotStore.shared
        var connectionChanged = false
        var snapshotChanged = false

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

        if store.isConfigured, let data = payload[Key.snapshot] as? Data,
           let snapshot = try? TokenSnapshot(jsonData: data),
           snapshot.schemaVersion <= TokenSnapshot.currentSchemaVersion {
            // The watch fetches the Hub itself too; keep whichever is newer.
            let cached = snapshots.load()
            if cached.map({ snapshot.fetchedAt > $0.fetchedAt }) ?? true {
                try? snapshots.save(snapshot)
                snapshotChanged = true
            }
        }

        guard connectionChanged || snapshotChanged else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        // A complication transfer exists to update the face now.
        reloadComplicationsLocked(force: connectionChanged || !carriesConnection)
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
