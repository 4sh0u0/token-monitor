import Foundation
import TokenMonitorKit
import WatchConnectivity

/// Hands the Hub connection and the latest snapshot to the watch app.
///
/// The watch cannot read the iPhone's Keychain or App Group, so it keeps its
/// own copy of both (which is also what its complications read). The secret
/// crosses only WatchConnectivity's encrypted channel.
///
/// Call `activate()` once from the app's `init` — not from a view's
/// `onAppear` — so a background launch caused by a watch request is answered.
/// Call `push(connection:snapshot:)` after saving or clearing the settings and
/// after every snapshot write; the bridge dedupes and throttles.
///
/// The payload keys are mirrored by `WatchSessionBridge` in the watch app
/// target; change both together and bump `protocolVersion` when a key's
/// meaning changes.
final class PhoneSessionBridge: NSObject, @unchecked Sendable {
    // @unchecked: every mutable property below is confined to `queue`.

    static let shared = PhoneSessionBridge()

    enum Key {
        static let version = "v"
        /// Int64 milliseconds, strictly increasing across launches: the watch
        /// drops anything older than the connection state it already applied
        /// (context, complication transfer and sync reply can arrive out of
        /// order).
        static let revision = "rev"
        /// Bool, present in every payload that states the connection; false
        /// means the user disconnected the Hub.
        static let connected = "connected"
        /// JSON-encoded `HubConnection` (URL + secret), when connected.
        static let hub = "hub"
        /// `TokenSnapshot.jsonData()`.
        static let snapshot = "snapshot"
        static let request = "request"
        static let syncRequest = "sync"
    }

    static let protocolVersion = 1
    /// Snapshot-only context updates closer together than this collapse into
    /// one trailing update; the open watch app fetches the Hub itself.
    static let minimumSnapshotInterval: TimeInterval = 60
    /// Complication transfers wake the watch app but come out of a daily
    /// budget of about 50, so they are spaced out, more so once it runs low.
    static let complicationInterval: TimeInterval = 20 * 60
    static let lowBudgetComplicationInterval: TimeInterval = 60 * 60
    static let lowBudgetThreshold = 10

    private enum DefaultsKey {
        static let revision = "watchSync.lastRevision"
        static let lastComplicationTransfer = "watchSync.lastComplicationTransfer"
    }

    private struct State: Equatable {
        var connection: HubConnection?
        var snapshot: Data?
    }

    private let queue = DispatchQueue(label: "TokenMonitor.PhoneSessionBridge", qos: .utility)
    // Bridge-private bookkeeping; nothing here is shared with the extensions.
    private let defaults = UserDefaults.standard
    /// Nil until the first `push` (or a load from the stores) this launch.
    private var state: State?
    private var lastContextSentAt: Date?
    private var trailingFlush: DispatchWorkItem?
    /// Resend even when `applicationContext` already holds the same content:
    /// after switching watches or reinstalling the watch app that copy
    /// describes a watch that no longer has it.
    private var bypassDedupe = false

    private override init() {
        super.init()
    }

    /// Starts the session. No-op where WatchConnectivity is unsupported
    /// (iPad); safe to call more than once.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Sends the current state to the watch. A nil `connection` disconnects
    /// the watch (and drops its snapshot); a nil `snapshot` with the same Hub
    /// keeps the last one sent, and so does one read from another Hub.
    func push(connection: HubConnection?, snapshot: TokenSnapshot?) {
        guard WCSession.isSupported() else { return }
        let snapshotData = Self.snapshotData(snapshot, for: connection)
        queue.async { [self] in
            var next = State(connection: connection, snapshot: snapshotData)
            if next.snapshot == nil, let connection, state?.connection?.baseURL == connection.baseURL {
                next.snapshot = state?.snapshot
            }
            state = next
            flush()
            if let snapshotData, connection != nil {
                transferComplicationIfDue(snapshotData)
            }
        }
    }

    // MARK: Sending (on `queue`)

    /// The session when the watch app can receive anything; until activation
    /// completes the state just waits in `state`.
    private func readySession() -> WCSession? {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return nil }
        return session
    }

    private func flush() {
        guard let session = readySession(), let state, let content = Self.content(of: state) else { return }
        let lastSent = session.applicationContext
        if !bypassDedupe, Self.sameContent(content, lastSent) {
            return
        }
        let connectionChanged = bypassDedupe || !Self.sameConnection(content, lastSent)
        if !connectionChanged, let lastContextSentAt {
            let wait = Self.minimumSnapshotInterval - Date().timeIntervalSince(lastContextSentAt)
            if wait > 0 {
                scheduleTrailingFlush(after: wait)
                return
            }
        }
        var context = content
        context[Key.revision] = NSNumber(value: nextRevision())
        do {
            try session.updateApplicationContext(context)
            lastContextSentAt = Date()
            bypassDedupe = false
            trailingFlush?.cancel()
            trailingFlush = nil
        } catch {
            // Not reachable through the system's queue right now (e.g. the
            // watch app was just removed): the next push or watch-state change
            // tries again.
        }
    }

    private func scheduleTrailingFlush(after delay: TimeInterval) {
        guard trailingFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.trailingFlush = nil
            self.flush()
        }
        trailingFlush = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func transferComplicationIfDue(_ snapshot: Data) {
        guard let session = readySession(), session.isComplicationEnabled else { return }
        let remaining = session.remainingComplicationUserInfoTransfers
        guard remaining > 0 else { return }
        let interval = remaining > Self.lowBudgetThreshold ? Self.complicationInterval : Self.lowBudgetComplicationInterval
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: DefaultsKey.lastComplicationTransfer)
        // `now < last`: the clock moved back; do not wait for it to catch up.
        guard last == 0 || now < last || now - last >= interval else { return }
        defaults.set(now, forKey: DefaultsKey.lastComplicationTransfer)
        session.transferCurrentComplicationUserInfo([
            Key.version: Self.protocolVersion,
            Key.revision: NSNumber(value: nextRevision()),
            Key.snapshot: snapshot
        ])
    }

    /// The saved settings, when nothing was pushed yet this launch (the watch
    /// app was installed or the session activated before the app pushed).
    private func loadStateIfNeeded() {
        guard state == nil else { return }
        let connection: HubConnection?
        do {
            connection = try HubConnectionStore.shared.loadConnection()
        } catch {
            // Keychain locked (before first unlock): stating "no connection"
            // now would disconnect the watch, so say nothing yet.
            return
        }
        state = State(connection: connection, snapshot: Self.snapshotData(SnapshotStore.shared.load(), for: connection))
    }

    /// The answer to the watch's `["request": "sync"]`.
    private func syncReply() -> [String: Any] {
        let connection: HubConnection?
        do {
            connection = try HubConnectionStore.shared.loadConnection()
        } catch {
            // No connection state rather than a false "disconnected".
            return [Key.version: Self.protocolVersion]
        }
        var snapshot: Data?
        if let connection {
            snapshot = Self.snapshotData(SnapshotStore.shared.load(), for: connection)
            if snapshot == nil, state?.connection?.baseURL == connection.baseURL {
                snapshot = state?.snapshot
            }
        }
        guard var reply = Self.content(of: State(connection: connection, snapshot: snapshot)) else {
            return [Key.version: Self.protocolVersion]
        }
        reply[Key.revision] = NSNumber(value: nextRevision())
        return reply
    }

    private func nextRevision() -> Int64 {
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        let last = (defaults.object(forKey: DefaultsKey.revision) as? NSNumber)?.int64Value ?? 0
        let revision = max(now, last + 1)
        defaults.set(NSNumber(value: revision), forKey: DefaultsKey.revision)
        return revision
    }

    // MARK: Payloads

    /// The snapshot's payload form, when it was read from `connection`'s Hub:
    /// the App Group file can still hold another Hub's numbers (a widget
    /// fetch that finished after a switch), and the watch must not show them.
    private static func snapshotData(_ snapshot: TokenSnapshot?, for connection: HubConnection?) -> Data? {
        guard let snapshot, snapshot.belongs(to: connection) else { return nil }
        return try? snapshot.jsonData()
    }

    private static func content(of state: State) -> [String: Any]? {
        var content: [String: Any] = [Key.version: protocolVersion]
        guard let connection = state.connection else {
            content[Key.connected] = false
            return content
        }
        let encoder = JSONEncoder()
        // Stable bytes, so equal connections compare equal in the dedupe.
        encoder.outputFormatting = [.sortedKeys]
        guard let hub = try? encoder.encode(connection) else { return nil }
        content[Key.connected] = true
        content[Key.hub] = hub
        if let snapshot = state.snapshot {
            content[Key.snapshot] = snapshot
        }
        return content
    }

    private static func sameConnection(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        (left[Key.version] as? Int) == (right[Key.version] as? Int)
            && (left[Key.connected] as? Bool) == (right[Key.connected] as? Bool)
            && (left[Key.hub] as? Data) == (right[Key.hub] as? Data)
    }

    private static func sameContent(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        sameConnection(left, right) && (left[Key.snapshot] as? Data) == (right[Key.snapshot] as? Data)
    }
}

extension PhoneSessionBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        queue.async { [self] in
            loadStateIfNeeded()
            flush()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch: activate for it and resend.
    func sessionDidDeactivate(_ session: WCSession) {
        queue.async { [self] in
            bypassDedupe = true
            lastContextSentAt = nil
        }
        session.activate()
    }

    /// Pairing, (re)installing the watch app or adding a complication.
    func sessionWatchStateDidChange(_ session: WCSession) {
        queue.async { [self] in
            guard session.isPaired, session.isWatchAppInstalled else { return }
            bypassDedupe = true
            loadStateIfNeeded()
            flush()
            if let state, state.connection != nil, let snapshot = state.snapshot {
                transferComplicationIfDue(snapshot)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[Key.request] as? String == Key.syncRequest else {
            replyHandler([:])
            return
        }
        queue.async { [self] in
            replyHandler(syncReply())
        }
    }
}
