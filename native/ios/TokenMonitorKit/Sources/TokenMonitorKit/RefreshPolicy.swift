import Foundation

/// When the iOS widgets refresh, for one `widgetRefreshMinutes` choice.
public struct WidgetRefreshTiming: Sendable, Equatable {
    /// A cached snapshot younger than this is shown as is; an older one makes
    /// the timeline provider ask the Hub first.
    public var refreshAfter: TimeInterval
    /// The reload WidgetKit is asked for (`.after(now + reloadInterval)`).
    /// Only a request: the daily budget decides when it actually happens.
    public var reloadInterval: TimeInterval
    /// Data older than this is marked stale. Deliberately well past
    /// `reloadInterval`, because budget-limited reloads routinely run late.
    public var staleAfter: TimeInterval

    public init(refreshAfter: TimeInterval, reloadInterval: TimeInterval, staleAfter: TimeInterval) {
        self.refreshAfter = refreshAfter
        self.reloadInterval = reloadInterval
        self.staleAfter = staleAfter
    }
}

/// How the watch app refreshes while on screen, for one `watchRefreshSeconds`
/// choice.
public struct WatchRefreshTiming: Sendable, Equatable {
    /// The poll interval while the app is active.
    public var pollInterval: TimeInterval
    /// A snapshot younger than this is not refetched when the app becomes
    /// active again (raising the wrist twice should not cost two requests).
    public var minimumRefreshAge: TimeInterval
    /// Older than this, the UI marks the numbers as possibly stale.
    public var staleAge: TimeInterval

    public init(pollInterval: TimeInterval, minimumRefreshAge: TimeInterval, staleAge: TimeInterval) {
        self.pollInterval = pollInterval
        self.minimumRefreshAge = minimumRefreshAge
        self.staleAge = staleAge
    }
}

/// When the watch complications refresh, for one `complicationRefreshMinutes`
/// choice.
public struct ComplicationRefreshTiming: Sendable, Equatable {
    /// A cache older than this is worth one Hub request.
    public var refreshAge: TimeInterval
    /// The reload requested while a Hub is configured.
    public var reloadInterval: TimeInterval
    /// The reload requested while no Hub is configured (not user-tunable).
    public var unconfiguredReloadInterval: TimeInterval
    /// Older than this, the rectangular usage complication says how old.
    public var staleAge: TimeInterval

    public init(refreshAge: TimeInterval, reloadInterval: TimeInterval, unconfiguredReloadInterval: TimeInterval, staleAge: TimeInterval) {
        self.refreshAge = refreshAge
        self.reloadInterval = reloadInterval
        self.unconfiguredReloadInterval = unconfiguredReloadInterval
        self.staleAge = staleAge
    }
}

/// The refresh preferences turned into timings (round-2 plan §3.10). Every
/// default choice reproduces the round-1 constants exactly.
public enum RefreshPolicy {
    /// The app's poll interval, nil in Live mode (the SSE stream with the
    /// round-1 backoff, polling fallback and first-event grace, which stay in
    /// the app). Pull to refresh always works.
    public static func appPollInterval(_ mode: AppRefreshMode) -> TimeInterval? {
        mode == .live ? nil : TimeInterval(mode.rawValue)
    }

    /// N minutes → refresh after `max(5, N − 5)` min, reload every N min,
    /// stale after 2N min. The default 15 gives round 1's 10 / 15 / 30.
    public static func widget(_ interval: WidgetRefreshInterval) -> WidgetRefreshTiming {
        let minutes = TimeInterval(interval.rawValue)
        return WidgetRefreshTiming(
            refreshAfter: max(5, minutes - 5) * 60,
            reloadInterval: minutes * 60,
            staleAfter: 2 * minutes * 60
        )
    }

    /// The watch app's poll interval while on screen.
    public static func watchPollInterval(_ interval: WatchRefreshInterval) -> TimeInterval {
        TimeInterval(interval.rawValue)
    }

    /// N seconds → poll every N, skip a re-activation fetch younger than
    /// `min(30 s, N / 2)`, stale after `max(15 min, 2N)`. The default 60 s
    /// gives round 1's 60 s / 30 s / 15 min.
    public static func watch(_ interval: WatchRefreshInterval) -> WatchRefreshTiming {
        let seconds = TimeInterval(interval.rawValue)
        return WatchRefreshTiming(
            pollInterval: seconds,
            minimumRefreshAge: min(30, seconds / 2),
            staleAge: max(15 * 60, 2 * seconds)
        )
    }

    /// N minutes → refresh age and reload interval both N; 60 min while no
    /// Hub is configured; stale after `max(60 min, 2N)`. The default 20 gives
    /// round 1's 20 / 20 / 60 / 60 minutes.
    public static func complication(_ interval: ComplicationRefreshInterval) -> ComplicationRefreshTiming {
        let seconds = TimeInterval(interval.rawValue) * 60
        return ComplicationRefreshTiming(
            refreshAge: seconds,
            reloadInterval: seconds,
            unconfiguredReloadInterval: 60 * 60,
            staleAge: max(60 * 60, 2 * seconds)
        )
    }

    /// The Status tab's re-check interval while it is visible, nil for
    /// manual.
    public static func serviceStatusInterval(_ refresh: ServiceStatusRefresh) -> TimeInterval? {
        refresh == .manual ? nil : TimeInterval(refresh.rawValue) / 1000
    }
}
