import Foundation
import Observation
import SwiftUI
import TokenMonitorKit
import WidgetKit

/// App-wide state: the saved Hub connection, the latest stats and how they
/// are kept live.
@MainActor
@Observable
final class AppModel {
    enum LiveState: Equatable {
        /// Not updating (backgrounded, not configured, or stopped by an error
        /// only the user can fix).
        case idle
        case connecting
        /// Receiving `GET /api/stats/stream`.
        case streaming
        /// The stream kept failing; reading `GET /api/stats` every 30 s.
        case polling
    }

    // MARK: Navigation

    var selectedTab: AppTab = .overview
    var selectedPeriod: UsagePeriodKind = .today

    // MARK: Connection and data

    private(set) var connection: HubConnection? = nil
    /// A Hub URL is saved, even when the Keychain secret is not readable yet.
    private(set) var isConfigured: Bool
    private(set) var stats: HubStats? = nil
    /// When this phone last received stats (not how fresh the Hub's data is).
    private(set) var lastUpdated: Date? = nil
    private(set) var issue: HubIssue? = nil
    private(set) var liveState: LiveState = .idle

    var needsOnboarding: Bool { !isConfigured }

    /// The saved Hub URL, readable even while the secret is not.
    var savedBaseURL: URL? { store.baseURL }

    // MARK: Tuning

    /// The product promises seconds-fresh numbers while the app is open; this
    /// is only the fallback when the stream cannot be held open.
    private static let pollInterval: Duration = .seconds(30)
    private static let streamFailuresBeforePolling = 4
    /// While polling, the stream is retried every this many polls (~5 min).
    private static let pollsBetweenStreamAttempts = 10
    /// A proxy that buffers `text/event-stream` holds the first snapshot back
    /// until its idle timeout; after this grace a plain read fills the screen.
    private static let firstEventGrace: Duration = .seconds(8)
    private static let maxBackoffSeconds: Double = 30
    /// WidgetKit budgets reloads, so fresh data reloads timelines at most this
    /// often; settings changes reload immediately.
    private static let widgetReloadInterval: TimeInterval = 5 * 60
    /// Unchanged stats still refresh the cached snapshot's age this often.
    private static let snapshotRefreshInterval: TimeInterval = 60

    private let store: HubConnectionStore
    private let snapshotStore: SnapshotStore
    @ObservationIgnored private var liveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var liveGeneration = 0
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var hasActivatedOnce = false
    @ObservationIgnored private var lastWidgetReload: Date? = nil
    @ObservationIgnored private var lastSnapshotSave: Date? = nil

    init(store: HubConnectionStore = .shared, snapshotStore: SnapshotStore = .shared) {
        self.store = store
        self.snapshotStore = snapshotStore
        self.isConfigured = store.isConfigured
        loadConnection()
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isSceneActive = true
            // Prewarming can launch the app before the first unlock, when the
            // Keychain refuses reads; try again once the user is here.
            if connection == nil, store.isConfigured { loadConnection() }
            if !hasActivatedOnce {
                hasActivatedOnce = true
                // Re-sends the saved connection, so a newly paired or
                // reinstalled watch gets it without a settings change. Never
                // push nil here: an unreadable Keychain is not a disconnect.
                if let connection {
                    PhoneSessionBridge.shared.push(connection: connection, snapshot: snapshotStore.load())
                }
            }
            startLiveUpdates()
        case .background:
            isSceneActive = false
            stopLiveUpdates()
        default:
            // `.inactive` is transient (app switcher, Control Center): keep the stream.
            break
        }
    }

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .dashboard(let period):
            selectedTab = .overview
            if let period { selectedPeriod = period }
        case .limits:
            selectedTab = .limits
        case .devices:
            selectedTab = .devices
        case .settings:
            selectedTab = .settings
        }
    }

    // MARK: Settings

    /// Saves a new or edited connection, then pushes it to the watch, reloads
    /// widgets and restarts live updates.
    /// - Throws: the Keychain error when the secret cannot be stored.
    func save(_ newConnection: HubConnection) throws {
        let hubChanged = store.baseURL != newConnection.baseURL
        try store.save(newConnection)
        if hubChanged {
            // Another Hub's numbers must not stay on screen, in widgets or on the watch.
            stats = nil
            lastUpdated = nil
            lastSnapshotSave = nil
            try? snapshotStore.clear()
        }
        connection = newConnection
        isConfigured = true
        issue = nil
        PhoneSessionBridge.shared.push(connection: newConnection, snapshot: hubChanged ? nil : snapshotStore.load())
        reloadWidgets(force: true)
        restartLiveUpdates()
    }

    /// Forgets the Hub on this phone, its widgets and the watch.
    func disconnect() {
        stopLiveUpdates()
        try? store.clear()
        try? snapshotStore.clear()
        connection = nil
        isConfigured = store.isConfigured
        stats = nil
        lastUpdated = nil
        lastSnapshotSave = nil
        issue = nil
        selectedTab = .overview
        PhoneSessionBridge.shared.push(connection: nil, snapshot: nil)
        reloadWidgets(force: true)
    }

    // MARK: Refresh

    /// Pull to refresh: one stats read, independent of the live stream.
    func refresh() async {
        if connection == nil, store.isConfigured { loadConnection() }
        guard let connection else {
            if !store.isConfigured { issue = HubIssue(kind: .notConfigured) }
            return
        }
        await fetchOnce(HubClient(connection: connection))
        // A refresh that worked after live updates gave up (e.g. the secret
        // was fixed on the Hub) brings them back.
        if issue == nil { startLiveUpdates() }
    }

    // MARK: Private

    private func loadConnection() {
        isConfigured = store.isConfigured
        do {
            connection = try store.loadConnection()
            if issue?.kind == .secretLocked { issue = nil }
        } catch {
            connection = nil
            issue = HubIssue(error: error, connection: nil)
        }
    }

    private func apply(_ newStats: HubStats, from source: HubConnection) {
        // A response from a connection that has since been replaced or removed.
        guard source == connection else { return }
        let now = Date()
        let changed = newStats != stats
        if changed { stats = newStats }
        lastUpdated = now
        if issue != nil { issue = nil }

        let snapshotDue = lastSnapshotSave.map { now.timeIntervalSince($0) >= Self.snapshotRefreshInterval } ?? true
        guard changed || snapshotDue else { return }
        let snapshot = TokenSnapshot(stats: newStats, fetchedAt: now)
        do {
            try snapshotStore.save(snapshot)
            lastSnapshotSave = now
        } catch {
            // Widgets keep the previous file; the next update tries again.
        }
        PhoneSessionBridge.shared.push(connection: source, snapshot: snapshot)
        reloadWidgets(force: false, now: now)
    }

    private func reloadWidgets(force: Bool, now: Date = Date()) {
        if !force, let last = lastWidgetReload, now.timeIntervalSince(last) < Self.widgetReloadInterval { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    @discardableResult
    private func fetchOnce(_ client: HubClient) async -> HubIssue? {
        do {
            let stats = try await client.stats()
            apply(stats, from: client.connection)
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            guard client.connection == connection else { return nil }
            let failure = HubIssue(error: error, connection: client.connection)
            issue = failure
            return failure
        }
    }

    // MARK: Live updates

    private func startLiveUpdates() {
        guard isSceneActive, liveTask == nil, let connection else { return }
        liveGeneration += 1
        let generation = liveGeneration
        liveTask = Task { [weak self] in
            await self?.runLiveUpdates(connection: connection)
            self?.liveUpdatesEnded(generation: generation)
        }
    }

    private func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        liveGeneration += 1
        liveState = .idle
    }

    private func restartLiveUpdates() {
        stopLiveUpdates()
        startLiveUpdates()
    }

    private func liveUpdatesEnded(generation: Int) {
        // A cancelled run must not clear the task that replaced it.
        guard generation == liveGeneration else { return }
        liveTask = nil
        liveState = .idle
    }

    /// Streams while it works, reconnecting with capped exponential backoff
    /// and jitter; polls when the stream keeps failing; stops on errors that
    /// only new settings can fix.
    private func runLiveUpdates(connection: HubConnection) async {
        let client = HubClient(connection: connection)
        var failures = 0
        while !Task.isCancelled {
            if failures >= Self.streamFailuresBeforePolling {
                liveState = .polling
                for _ in 0..<Self.pollsBetweenStreamAttempts {
                    if let failure = await fetchOnce(client), failure.stopsLiveUpdates { return }
                    try? await Task.sleep(for: Self.pollInterval)
                    if Task.isCancelled { return }
                }
                // One more stream failure puts it straight back to polling.
                failures = Self.streamFailuresBeforePolling - 1
                continue
            }

            liveState = .connecting
            let outcome = await consumeStream(client)
            if Task.isCancelled { return }
            if let error = outcome.error {
                let failure = HubIssue(error: error, connection: connection)
                if failure.stopsLiveUpdates {
                    issue = failure
                    return
                }
                // A single drop (a Hub restart) reconnects quietly; keep showing
                // the last numbers and only report a failure that persists.
                if outcome.receivedStats {
                    failures = 0
                } else {
                    failures += 1
                    if stats == nil || failures >= 2 { issue = failure }
                }
            } else {
                // The Hub closed the stream cleanly; reconnect soon.
                failures = outcome.receivedStats ? 0 : failures + 1
            }
            liveState = .connecting
            try? await Task.sleep(for: Self.backoff(afterFailures: failures))
        }
    }

    private func consumeStream(_ client: HubClient) async -> (receivedStats: Bool, error: Error?) {
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.firstEventGrace)
            guard !Task.isCancelled else { return }
            await self?.fetchOnce(client)
        }
        defer { watchdog.cancel() }
        var received = false
        do {
            for try await update in client.statsStream() {
                if Task.isCancelled { break }
                if !received {
                    received = true
                    watchdog.cancel()
                    liveState = .streaming
                }
                apply(update, from: client.connection)
            }
            return (received, nil)
        } catch {
            return (received, error)
        }
    }

    private static func backoff(afterFailures failures: Int) -> Duration {
        let exponent = min(max(failures - 1, 0), 6)
        let base = min(maxBackoffSeconds, pow(2, Double(exponent)))
        // Jitter keeps several phones (or a phone and its watch) from
        // reconnecting to a restarted Hub in lockstep.
        let jittered = base + Double.random(in: 0...(base * 0.3))
        return .milliseconds(Int(jittered * 1000))
    }
}
