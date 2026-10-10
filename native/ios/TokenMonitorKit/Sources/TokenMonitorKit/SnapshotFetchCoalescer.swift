import Foundation

/// Shares one Hub fetch between the timeline requests of a widget or
/// complication extension.
///
/// WidgetKit asks for every placed widget's timeline at once; each one
/// fetching and decoding its own copy of the full `/api/stats` response is how
/// an extension exceeds its memory limit. Callers for the same Hub join the
/// fetch in flight, and a fetch that just finished is reused for
/// `reuseWindow` by callers that read the cache a moment too early.
///
/// Everything is keyed by `HubConnection.snapshotKey`, so nothing of the
/// previous Hub is handed out after a Hub switch: its fetch in flight is
/// cancelled rather than decoded beside the new one, and its last result is
/// not reused.
public actor SnapshotFetchCoalescer {
    public let reuseWindow: TimeInterval

    private struct Fetch {
        let id: UInt64
        let hubKey: String
        let task: Task<TokenSnapshot?, Never>
    }

    private var inFlight: Fetch?
    private var lastFetchID: UInt64 = 0
    /// Keyed by the Hub it was fetched for, not by its own `hubKey`, which a
    /// snapshot of unknown origin does not have.
    private var lastFetched: (hubKey: String, snapshot: TokenSnapshot)?

    public init(reuseWindow: TimeInterval) {
        self.reuseWindow = reuseWindow
    }

    /// A snapshot of the Hub `hubKey` names, or nil when there is none to be had.
    /// - Parameters:
    ///   - hubKey: `snapshotKey` of the Hub the caller shows.
    ///   - force: skip the reuse window (a refresh button). A fetch already in
    ///     flight for the same Hub is still joined.
    ///   - now: the caller's clock, for the reuse window.
    ///   - fetch: reads the Hub. Returns a snapshot stamped with the Hub it was
    ///     read from (`SnapshotBuilder.snapshot(from:fetchedAt:hub:)`), or nil on any
    ///     failure, including the saved Hub changing meanwhile. It runs in a
    ///     task of its own, so a caller that goes away does not cancel a fetch
    ///     others joined; it is cancelled only when another Hub's fetch
    ///     replaces it.
    /// - Returns: nil also when the fetched snapshot does not `belong(to:)` `hubKey`.
    public func snapshot(
        hubKey: String,
        force: Bool = false,
        now: Date = Date(),
        fetch: @escaping @Sendable () async -> TokenSnapshot?
    ) async -> TokenSnapshot? {
        if let current = inFlight {
            if current.hubKey == hubKey {
                return Self.accepted(await current.task.value, for: hubKey)
            }
            // The Hub changed while the previous one was being read: that
            // result can no longer be shown.
            current.task.cancel()
            inFlight = nil
        }
        if !force, let last = lastFetched, last.hubKey == hubKey, isReusable(last.snapshot, at: now) {
            return last.snapshot
        }
        lastFetchID &+= 1
        let id = lastFetchID
        let task = Task<TokenSnapshot?, Never> { await fetch() }
        inFlight = Fetch(id: id, hubKey: hubKey, task: task)
        let result = Self.accepted(await task.value, for: hubKey)
        // Only this fetch's own entry: another Hub's fetch may have replaced it.
        if inFlight?.id == id { inFlight = nil }
        if let result, !task.isCancelled { lastFetched = (hubKey, result) }
        return result
    }

    /// A snapshot dated in the future (the clock moved back) is not reused.
    private func isReusable(_ snapshot: TokenSnapshot, at now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= -60 && age <= reuseWindow
    }

    private static func accepted(_ snapshot: TokenSnapshot?, for hubKey: String) -> TokenSnapshot? {
        guard let snapshot, snapshot.belongs(toHubKey: hubKey) else { return nil }
        return snapshot
    }
}
