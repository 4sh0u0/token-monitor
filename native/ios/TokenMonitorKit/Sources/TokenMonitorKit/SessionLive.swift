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
