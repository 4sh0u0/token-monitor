import Foundation

/// A session's live state (`sessionLive.js` `sessionActivityState`).
public enum SessionActivityState: String, Sendable, Codable, CaseIterable {
    /// The transcript moved recently and no turn end followed.
    case running
    /// The transcript said the turn finished (still within the window).
    case ended
    /// Quiet for longer than the window, or archived.
    case idle
}

/// How tight a session's context window is; `neutral` until it matters.
public enum ContextTone: String, Sendable, Codable, CaseIterable {
    /// ≤ 10 % left.
    case low
    /// ≤ 30 % left.
    case caution
    case neutral
}

/// A session's context-window reading.
public struct SessionContextGauge: Sendable, Hashable {
    public var contextTokens: Int
    public var contextWindow: Int
    /// 0–100, rounded.
    public var percentLeft: Int
    /// `100 - percentLeft`, so the two readings never disagree.
    public var percentUsed: Int
    public var tone: ContextTone

    public init(contextTokens: Int, contextWindow: Int, percentLeft: Int, percentUsed: Int, tone: ContextTone) {
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.percentLeft = percentLeft
        self.percentUsed = percentUsed
        self.tone = tone
    }

    /// The reading `metric` shows.
    public func percent(for metric: ContextMetric) -> Int {
        switch metric {
        case .used: return percentUsed
        case .remaining: return percentLeft
        }
    }
}

/// Time left on a session's prompt cache.
public struct PromptCacheCountdown: Sendable, Hashable {
    public var expiresAt: Date
    /// 300, 1800 or 3600.
    public var ttlSeconds: Int
    /// Whole minutes left, rounded up.
    public var minutes: Int

    public init(expiresAt: Date, ttlSeconds: Int, minutes: Int) {
        self.expiresAt = expiresAt
        self.ttlSeconds = ttlSeconds
        self.minutes = minutes
    }
}

/// Port of `src/shared/sessionLive.js`: whether a session is still being
/// written to, how much of its context window is left, and how long its
/// prompt cache has. Every surface that shows a session reads these, so the
/// list, the Overview module and the detail screen cannot disagree.
///
/// All of it is a function of `now`: re-evaluate at `nextChange(sessions:now:)`
/// (or at least each minute), never freeze it at fetch time. Times compare in
/// whole milliseconds, as the desktop's `Date.parse` values do.
public enum SessionLive {
    /// `RUNNING_WINDOW_MS`: a session written to within this long is live.
    public static let runningWindow: TimeInterval = 600
    /// The clients whose transcripts carry a prompt-cache reading.
    public static let promptCacheClients: Set<String> = ["claude", "codex"]
    /// The cache TTL tiers a reading may claim; anything else is ignored.
    public static let promptCacheTTLs: Set<Int> = [300, 1800, 3600]
    /// `CONTEXT_TONES`: at most this much left is `low` …
    public static let lowContextMaxPercentLeft = 10
    /// … and at most this much is `caution`.
    public static let cautionContextMaxPercentLeft = 30

    static let runningWindowMs: Int64 = 600_000
    static let minuteMs: Int64 = 60_000

    /// `isArchivedSession`: `archived`, `deleted` or `sourceDeleted`.
    public static func isArchived(_ session: HubSession) -> Bool {
        session.isArchived
    }

    /// `sessionActivityState`. Archived or never-timestamped sessions are
    /// idle. Within the window a `turnEnded == true` session has `ended`;
    /// `false` and absent both read as `running` (a future `lastUsedAt` counts
    /// as recent, as on the desktop).
    public static func state(_ session: HubSession, now: Date) -> SessionActivityState {
        if session.isArchived { return .idle }
        let last = milliseconds(session.lastUsedAt)
        guard last != 0 else { return .idle }
        let recent = milliseconds(now) - last <= runningWindowMs
        if session.turnEnded == true { return recent ? .ended : .idle }
        return recent ? .running : .idle
    }

    /// `isRunningSession`.
    public static func isRunning(_ session: HubSession, now: Date) -> Bool {
        state(session, now: now) == .running
    }

    /// `contextTone`: ≤ 10 % left is `low`, ≤ 30 % `caution`, else `neutral`.
    public static func contextTone(percentLeft: Int) -> ContextTone {
        if percentLeft <= lowContextMaxPercentLeft { return .low }
        if percentLeft <= cautionContextMaxPercentLeft { return .caution }
        return .neutral
    }

    /// `sessionContextRow`: the context reading whatever the session's state,
    /// nil unless both halves are positive. More tokens than the window fits
    /// reads as 0 % left rather than negative headroom.
    public static func contextReading(_ session: HubSession) -> SessionContextGauge? {
        let tokens = session.contextTokens
        let window = session.contextWindow
        guard tokens > 0, window > 0 else { return nil }
        let left = Double(window - tokens) / Double(window) * 100
        // Clamped as a Double first: an overfull reading can be hugely
        // negative, and `Int` is 32-bit on Apple Watch.
        let percentLeft = Int(min(100, max(0, JSCompat.round(left))))
        return SessionContextGauge(
            contextTokens: tokens,
            contextWindow: window,
            percentLeft: percentLeft,
            percentUsed: 100 - percentLeft,
            tone: contextTone(percentLeft: percentLeft)
        )
    }

    /// `sessionContextForRow`: the reading a row shows — nil once the
    /// session is idle (it survives a finished turn until the window closes).
    public static func context(_ session: HubSession, now: Date) -> SessionContextGauge? {
        guard state(session, now: now) != .idle else { return nil }
        return contextReading(session)
    }

    /// `sessionPromptCacheForRow`. Nil when the session is archived, its
    /// client is not claude or codex, the TTL is not 300/1800/3600 s, the
    /// observation lies in the future, or the cache has already expired.
    /// `minutes` rounds up.
    public static func promptCache(_ session: HubSession, now: Date) -> PromptCacheCountdown? {
        guard !session.isArchived,
              promptCacheClients.contains(session.client),
              let cache = session.promptCache else { return nil }
        let observed = milliseconds(cache.observedAt)
        guard observed != 0, promptCacheTTLs.contains(cache.ttlSeconds) else { return nil }
        let clock = milliseconds(now)
        guard observed <= clock else { return nil }
        let expires = observed + Int64(cache.ttlSeconds) * 1000
        guard expires > clock else { return nil }
        let minutes = Int((expires - clock + minuteMs - 1) / minuteMs)
        return PromptCacheCountdown(expiresAt: date(milliseconds: expires), ttlSeconds: cache.ttlSeconds, minutes: minutes)
    }

    /// `nextPromptCacheChangeAt`: the soonest moment a countdown's minute
    /// label changes; nil when no session has one.
    public static func nextPromptCacheChange(sessions: [HubSession], now: Date) -> Date? {
        let next = nextPromptCacheChangeMs(sessions: sessions, clock: milliseconds(now))
        return next == 0 ? nil : date(milliseconds: next)
    }

    /// `nextSessionStatusChangeAt`: the soonest of the next cache-label change
    /// and the first millisecond at which a live (running or ended) session
    /// leaves the window. Re-render then — the desktop also caps the wait at
    /// 60 s. Nil when nothing will change on its own.
    public static func nextChange(sessions: [HubSession], now: Date) -> Date? {
        let clock = milliseconds(now)
        var next = nextPromptCacheChangeMs(sessions: sessions, clock: clock)
        for session in sessions where !session.isArchived {
            let last = milliseconds(session.lastUsedAt)
            let expiry = last + runningWindowMs + 1
            if last != 0, expiry > clock, next == 0 || expiry < next { next = expiry }
        }
        return next == 0 ? nil : date(milliseconds: next)
    }

    static func nextPromptCacheChangeMs(sessions: [HubSession], clock: Int64) -> Int64 {
        let now = date(milliseconds: clock)
        var next: Int64 = 0
        for session in sessions {
            guard let reading = promptCache(session, now: now) else { continue }
            let boundary = milliseconds(reading.expiresAt) - Int64(reading.minutes - 1) * minuteMs
            if next == 0 || boundary < next { next = boundary }
        }
        return next
    }

    /// Whole epoch milliseconds, the desktop's `Date.parse` value; 0 for nil
    /// (the desktop's "no timestamp").
    static func milliseconds(_ date: Date?) -> Int64 {
        guard let date else { return 0 }
        let value = (date.timeIntervalSince1970 * 1000).rounded()
        guard value.isFinite, abs(value) < 8.64e15 else { return 0 }
        return Int64(value)
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
