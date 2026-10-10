import Foundation

// Port of `src/electron/renderer/sessionRows.js` (rows, background-review
// grouping, the per-session labels), the Overview module's recent list
// (`edgeDock/presentation.js` `sessionSourceRows`/`recentSessionRows`) and
// `breakdownRenderPolicy.js` paging.
//
// Values only: the Kit says *what* a row shows and the targets word it.
// "N call(s)", "N tok/s" and "N models" are untranslated literals on the
// desktop (D-UNLOCALIZED), so targets print them with `Text(verbatim:)`;
// "Archived", "Codex Auto Review", "{count} background runs", "Latest
// {time}" and "Cache {minutes}m" are localized there.

/// `sessionModelLabel`: what a session row says about its models.
public enum SessionModelLabel: Sendable, Hashable {
    /// No model reported tokens.
    case none
    /// Exactly one model id.
    case single(String)
    /// "N models" (an untranslated literal on the desktop).
    case count(Int)
}

/// One piece of a session's activity line, in desktop order:
/// Archived · time · calls · cache hit · tok/s.
public enum SessionActivityPart: Sendable, Hashable {
    /// The source is archived or deleted (`session.archived`, localized).
    case archived
    /// `compactSessionTime`: `HH:mm` on the same local day, else `MM/DD HH:mm`.
    case time(String)
    /// "N call" / "N calls" — en-US grouped, untranslated.
    case calls(Int)
    /// The cache-hit share: `"88%"`, `"<1%"`.
    case cacheHit(String)
    /// "N tok/s" — en-US grouped, untranslated.
    case tokensPerSecond(Int)
}

/// A session row's title line.
public enum SessionRowName: Sendable, Hashable {
    /// The synced title (only when the Hub sent one and titles are enabled).
    case title(String)
    /// "Claude Code · claude-sonnet-4-5" / "OpenCode · 3 models". A nil label
    /// is a session with no client, which the desktop calls "Session".
    case tool(clientLabel: String?, model: SessionModelLabel)
    /// The background-review group ("Codex Auto Review",
    /// `sessions.backgroundReviews`).
    case backgroundReviews
}

/// The line under a row's title.
public enum SessionRowSubtitle: Sendable, Hashable {
    /// A titled session names its tool and model here.
    case tool(clientLabel: String?, model: SessionModelLabel)
    /// An untitled session shows its activity here.
    case activity([SessionActivityPart])
    /// The background-review group: "Latest {time}" (`sessions.
    /// backgroundReviewLatest`, omitted when nil) and the newest run's
    /// compact tokens (omitted when 0), joined with " · ".
    case reviewSummary(latestTime: String?, latestTokens: Int)
}

/// One line of a multi-model session's model tooltip
/// (`sessionModelTooltipEntries`).
public struct SessionModelShare: Sendable, Hashable, Identifiable {
    /// Nil for the trailing remainder no model claimed ("Unclassified",
    /// `dashboard.tooltip.unclassified`).
    public var model: String?
    public var tokens: Int
    /// Share of `max(totalTokens, attributed)`, 0–100 (unrounded; label it
    /// with `AttributionRows.detailPercentLabel`).
    public var percent: Double

    public init(model: String?, tokens: Int, percent: Double) {
        self.model = model
        self.tokens = tokens
        self.percent = percent
    }

    public var id: String { model ?? AttributionRows.unattributedKey }
}

/// A row of the Sessions list: one session, or the background-review group.
public struct SessionRow: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case session(HubSession)
        /// The background-review runs, newest first.
        case backgroundReviews([HubSession])
    }

    /// The desktop row key: `session:<map key>`, or
    /// `session-group:codex-auto-review` for the group.
    public var id: String
    public var kind: Kind
    /// The session's client id (`codex` for the group).
    public var client: String
    /// The catalog label for `client`; nil when the session has no client.
    public var clientLabel: String?
    public var name: SessionRowName
    public var subtitle: SessionRowSubtitle?
    /// The activity parts (empty for the group). A titled row shows them on
    /// their own line (`activityLine`); an untitled row's subtitle is them.
    public var activity: [SessionActivityPart]
    /// `sessionIdLabel` (nil when the id says nothing useful). The desktop
    /// drops it from rows that already show an activity line.
    public var idLabel: String?
    public var tokens: Int
    public var costUsd: Double
    public var unpricedTokens: Int?
    /// `lastUsedAt || startedAt` (the group: its newest run).
    public var sortTime: Date?
    /// `compactSessionTime(sortTime)`; nil without a time.
    public var timeLabel: String?
    public var modelLabel: SessionModelLabel
    public var state: SessionActivityState
    /// The gauge the row shows (nil once idle).
    public var context: SessionContextGauge?
    /// The context reading whatever the state (nil for archived sessions);
    /// the desktop's cache tooltip quotes it.
    public var contextSnapshot: SessionContextGauge?
    public var promptCache: PromptCacheCountdown?
    public var isArchived: Bool
    /// A `background-review` run (never true for the group itself).
    public var isBackgroundReview: Bool
    /// The model tooltip (only for two or more models).
    public var modelShares: [SessionModelShare]
    /// Output tok/s, unrounded; 0 without timing.
    public var tokensPerSecond: Double
    /// Cache hits as % of input; nil without cache traffic.
    public var cacheHitPercent: Double?
    /// The group's runs as rows, newest first; empty otherwise.
    public var reviewRows: [SessionRow]

    public init(
        id: String,
        kind: Kind,
        client: String,
        clientLabel: String?,
        name: SessionRowName,
        subtitle: SessionRowSubtitle?,
        activity: [SessionActivityPart] = [],
        idLabel: String? = nil,
        tokens: Int,
        costUsd: Double,
        unpricedTokens: Int? = nil,
        sortTime: Date? = nil,
        timeLabel: String? = nil,
        modelLabel: SessionModelLabel = .none,
        state: SessionActivityState = .idle,
        context: SessionContextGauge? = nil,
        contextSnapshot: SessionContextGauge? = nil,
        promptCache: PromptCacheCountdown? = nil,
        isArchived: Bool = false,
        isBackgroundReview: Bool = false,
        modelShares: [SessionModelShare] = [],
        tokensPerSecond: Double = 0,
        cacheHitPercent: Double? = nil,
        reviewRows: [SessionRow] = []
    ) {
        self.id = id
        self.kind = kind
        self.client = client
        self.clientLabel = clientLabel
        self.name = name
        self.subtitle = subtitle
        self.activity = activity
        self.idLabel = idLabel
        self.tokens = tokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.sortTime = sortTime
        self.timeLabel = timeLabel
        self.modelLabel = modelLabel
        self.state = state
        self.context = context
        self.contextSnapshot = contextSnapshot
        self.promptCache = promptCache
        self.isArchived = isArchived
        self.isBackgroundReview = isBackgroundReview
        self.modelShares = modelShares
        self.tokensPerSecond = tokensPerSecond
        self.cacheHitPercent = cacheHitPercent
        self.reviewRows = reviewRows
    }

    /// The session behind an ordinary row.
    public var session: HubSession? {
        if case let .session(session) = kind { return session }
        return nil
    }

    /// The background-review group row.
    public var isReviewGroup: Bool {
        if case .backgroundReviews = kind { return true }
        return false
    }

    /// The group's run count ("{count} background runs"); 0 otherwise.
    public var reviewCount: Int {
        if case let .backgroundReviews(runs) = kind { return runs.count }
        return 0
    }

    public var isRunning: Bool { state == .running }

    /// The separate activity line a titled row shows; nil otherwise.
    public var activityLine: [SessionActivityPart]? {
        guard case .title = name, !activity.isEmpty else { return nil }
        return activity
    }

    /// The prompt-cache countdown takes the gauge slot only when there is no
    /// context gauge (`updateRowContext`).
    public var showsPromptCache: Bool { promptCache != nil && context == nil }
}

/// One page of the Sessions list (`breakdownPage`).
public struct SessionPage: Sendable, Hashable {
    public var rows: [SessionRow]
    /// 0-based, clamped to the pages that exist.
    public var index: Int
    public var pageCount: Int
    public var pageSize: Int
    /// 1-based first row on the page; 0 for an empty list.
    public var start: Int
    /// 1-based last row on the page.
    public var end: Int
    public var total: Int
    /// More than one page; the pager shows only then.
    public var isPaginated: Bool

    public init(rows: [SessionRow], index: Int, pageCount: Int, pageSize: Int, start: Int, end: Int, total: Int, isPaginated: Bool) {
        self.rows = rows
        self.index = index
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.start = start
        self.end = end
        self.total = total
        self.isPaginated = isPaginated
    }
}

/// The Overview module's name for a recent session: title, else project,
/// else the first 12 characters of its id, else "—".
public enum RecentSessionName: Sendable, Hashable {
    case title(String)
    case project(String)
    case sessionID(String)
    case none
}

/// How long ago a session was active (`homeSessionAgo`, worded with
/// `edgeDock.ago*`).
public enum SessionAge: Sendable, Hashable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
}

/// A row of the Overview Sessions module.
public struct RecentSession: Sendable, Hashable, Identifiable {
    /// The period map key (`client:sessionId`).
    public var id: String
    public var session: HubSession
    /// The client id, trimmed and lower-cased.
    public var client: String
    public var name: RecentSessionName
    public var modelLabel: SessionModelLabel
    public var modelShares: [SessionModelShare]
    public var activityTime: Date?
    public var state: SessionActivityState
    public var context: SessionContextGauge?
    public var promptCache: PromptCacheCountdown?

    public init(
        id: String,
        session: HubSession,
        client: String,
        name: RecentSessionName,
        modelLabel: SessionModelLabel,
        modelShares: [SessionModelShare],
        activityTime: Date?,
        state: SessionActivityState,
        context: SessionContextGauge?,
        promptCache: PromptCacheCountdown?
    ) {
        self.id = id
        self.session = session
        self.client = client
        self.name = name
        self.modelLabel = modelLabel
        self.modelShares = modelShares
        self.activityTime = activityTime
        self.state = state
        self.context = context
        self.promptCache = promptCache
    }

    public var tokens: Int { session.totalTokens }
    public var costUsd: Double { session.costUsd }
    public var unpricedTokens: Int? { session.unpricedTokens }
    public var isRunning: Bool { state == .running }
    /// The cache badge shows only without a context gauge.
    public var showsPromptCache: Bool { promptCache != nil && context == nil }
}

/// The Overview module's list plus its "{count} running" header.
public struct RecentSessions: Sendable, Hashable {
    public var rows: [RecentSession]
    public var runningCount: Int

    public init(rows: [RecentSession], runningCount: Int) {
        self.rows = rows
        self.runningCount = runningCount
    }

    public static let empty = RecentSessions(rows: [], runningCount: 0)

    /// When the module next changes on its own (a running session going
    /// quiet, a cache label ticking); re-render then or within a minute.
    public func nextChange(now: Date) -> Date? {
        SessionLive.nextChange(sessions: rows.map(\.session), now: now)
    }
}

public enum SessionRows {
    /// `SESSION_BREAKDOWN_PAGE_SIZE`.
    public static let pageSize = 100
    /// The Overview module's row budget (running rows always stay).
    public static let recentLimit = 5
    public static let backgroundReviewGroupID = "session-group:codex-auto-review"

    // MARK: Rows

    /// `sessionRowsForPeriod` then `groupBackgroundReviewRows`: every session
    /// with tokens, newest first (then tokens, cost and name), Reasonix
    /// stand-ins dropped. With `groupBackgroundReviews` the background-review
    /// runs collapse into one group row appended at the end, as on the
    /// desktop. Titles show only when `titlesEnabled` and the Hub sent one.
    public static func rows(
        period: UsagePeriod,
        titlesEnabled: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current,
        groupBackgroundReviews: Bool = true
    ) -> [SessionRow] {
        rows(
            sessions: period.sessions,
            titlesEnabled: titlesEnabled,
            now: now,
            calendar: calendar,
            groupBackgroundReviews: groupBackgroundReviews
        )
    }

    /// `rows(period:…)` over a session list.
    public static func rows(
        sessions: [HubSession],
        titlesEnabled: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current,
        groupBackgroundReviews: Bool = true
    ) -> [SessionRow] {
        let clock = Self.clock(calendar)
        let built = sessions.enumerated().compactMap { offset, session -> (row: SessionRow, sortKey: String, offset: Int)? in
            guard !isReasonixSynthetic(session), session.totalTokens > 0 else { return nil }
            return (row(for: session, titlesEnabled: titlesEnabled, now: now, clock: clock), nameSortKey(session, titlesEnabled: titlesEnabled), offset)
        }
        let sorted = built.sorted { left, right in
            let leftTime = SessionLive.milliseconds(left.row.sortTime)
            let rightTime = SessionLive.milliseconds(right.row.sortTime)
            if leftTime != rightTime { return leftTime > rightTime }
            if left.row.tokens != right.row.tokens { return left.row.tokens > right.row.tokens }
            if left.row.costUsd != right.row.costUsd { return left.row.costUsd > right.row.costUsd }
            let names = UsageRowCollation.compare(left.sortKey, right.sortKey)
            if names != 0 { return names < 0 }
            return left.offset < right.offset
        }.map(\.row)
        return groupBackgroundReviews ? group(sorted, now: now, clock: clock) : sorted
    }

    /// One session's row at `now` (no filtering).
    public static func row(for session: HubSession, titlesEnabled: Bool = true, now: Date = Date(), calendar: Calendar = .current) -> SessionRow {
        row(for: session, titlesEnabled: titlesEnabled, now: now, clock: clock(calendar))
    }

    static func row(for session: HubSession, titlesEnabled: Bool, now: Date, clock: Calendar) -> SessionRow {
        let label = clientLabel(session.client)
        let model = modelLabel(session)
        let title = titlesEnabled ? displayTitle(session) : nil
        let time = compactTime(session.activityTime, now: now, clock: clock)
        var activity: [SessionActivityPart] = []
        if session.isArchived { activity.append(.archived) }
        if let time { activity.append(.time(time)) }
        if session.messageCount > 0 { activity.append(.calls(session.messageCount)) }
        if let hit = cacheHitLabel(session) { activity.append(.cacheHit(hit)) }
        if let rate = roundedTokenRate(session) { activity.append(.tokensPerSecond(rate)) }
        let name: SessionRowName
        let subtitle: SessionRowSubtitle?
        if let title {
            name = .title(title)
            subtitle = .tool(clientLabel: label, model: model)
        } else {
            name = .tool(clientLabel: label, model: model)
            subtitle = activity.isEmpty ? nil : .activity(activity)
        }
        return SessionRow(
            id: "session:\(session.id)",
            kind: .session(session),
            client: session.client,
            clientLabel: label,
            name: name,
            subtitle: subtitle,
            activity: activity,
            idLabel: sessionIDLabel(session.sessionId),
            tokens: session.totalTokens,
            costUsd: session.costUsd,
            unpricedTokens: (session.unpricedTokens ?? 0) > 0 ? session.unpricedTokens : nil,
            sortTime: session.activityTime,
            timeLabel: time,
            modelLabel: model,
            state: SessionLive.state(session, now: now),
            context: SessionLive.context(session, now: now),
            contextSnapshot: session.isArchived ? nil : SessionLive.contextReading(session),
            promptCache: SessionLive.promptCache(session, now: now),
            isArchived: session.isArchived,
            isBackgroundReview: isBackgroundReview(session),
            modelShares: modelShares(session),
            tokensPerSecond: tokenRate(session),
            cacheHitPercent: cacheHitPercent(session)
        )
    }

    /// `groupBackgroundReviewRows`: the background-review runs leave the list
    /// and come back as one group row at the end, holding them newest first.
    /// Its cost is the runs' sum; like the desktop it carries no unpriced
    /// count.
    public static func group(_ rows: [SessionRow], now: Date = Date(), calendar: Calendar = .current) -> [SessionRow] {
        group(rows, now: now, clock: clock(calendar))
    }

    static func group(_ rows: [SessionRow], now: Date, clock: Calendar) -> [SessionRow] {
        let primary = rows.filter { !$0.isBackgroundReview }
        let reviews = rows.filter(\.isBackgroundReview)
        guard !reviews.isEmpty else { return primary }
        let tokens = reviews.reduce(0) { $0 + $1.tokens }
        let cost = reviews.reduce(0.0) { $0 + $1.costUsd }
        let newest = reviews.reduce(Int64(0)) { max($0, SessionLive.milliseconds($1.sortTime)) }
        let ordered = reviews.enumerated().sorted { left, right in
            let leftTime = SessionLive.milliseconds(left.element.sortTime)
            let rightTime = SessionLive.milliseconds(right.element.sortTime)
            return leftTime != rightTime ? leftTime > rightTime : left.offset < right.offset
        }.map(\.element)
        let sortTime = newest == 0 ? nil : SessionLive.date(milliseconds: newest)
        let latestTime = compactTime(sortTime, now: now, clock: clock)
        let summary = SessionRow(
            id: backgroundReviewGroupID,
            kind: .backgroundReviews(ordered.compactMap(\.session)),
            client: "codex",
            clientLabel: clientLabel("codex"),
            name: .backgroundReviews,
            subtitle: .reviewSummary(latestTime: latestTime, latestTokens: ordered.first?.tokens ?? 0),
            tokens: tokens,
            costUsd: cost,
            sortTime: sortTime,
            timeLabel: latestTime,
            reviewRows: ordered
        )
        return primary + [summary]
    }

    /// `breakdownPage` for sessions: `size` rows per page, the index clamped.
    public static func page(_ rows: [SessionRow], index: Int, size: Int = pageSize) -> SessionPage {
        let size = max(1, size)
        guard rows.count > size else {
            return SessionPage(
                rows: rows, index: 0, pageCount: 1, pageSize: size,
                start: rows.isEmpty ? 0 : 1, end: rows.count, total: rows.count, isPaginated: false
            )
        }
        let pageCount = (rows.count + size - 1) / size
        let index = max(0, min(pageCount - 1, index))
        let offset = index * size
        let end = min(rows.count, offset + size)
        return SessionPage(
            rows: Array(rows[offset..<end]), index: index, pageCount: pageCount, pageSize: size,
            start: offset + 1, end: end, total: rows.count, isPaginated: true
        )
    }

    // MARK: Overview module

    /// The Overview Sessions module (`recentSessionRows(stats, 5,
    /// {includeRunningBeyondCap: true})`): month sessions, then today's not
    /// already seen, without background reviews or timestamps, newest first;
    /// the first `limit` plus every running session beyond them.
    public static func recent(
        month: UsagePeriod?,
        today: UsagePeriod?,
        limit: Int = recentLimit,
        titlesEnabled: Bool = true,
        now: Date = Date()
    ) -> RecentSessions {
        var seen = Set<String>()
        var entries: [(session: HubSession, time: Int64, offset: Int)] = []
        for period in [month, today] {
            for session in period?.sessions ?? [] {
                guard !seen.contains(session.id) else { continue }
                guard session.sessionKind != HubSession.backgroundReviewKind else { continue }
                guard let time = session.activityTime else { continue }
                seen.insert(session.id)
                entries.append((session, SessionLive.milliseconds(time), entries.count))
            }
        }
        entries.sort { $0.time != $1.time ? $0.time > $1.time : $0.offset < $1.offset }
        var rows: [RecentSession] = []
        for (index, entry) in entries.enumerated() {
            let state = SessionLive.state(entry.session, now: now)
            guard index < limit || state == .running else { continue }
            rows.append(recentRow(entry.session, state: state, titlesEnabled: titlesEnabled, now: now))
        }
        return RecentSessions(rows: rows, runningCount: rows.filter(\.isRunning).count)
    }

    static func recentRow(_ session: HubSession, state: SessionActivityState, titlesEnabled: Bool, now: Date) -> RecentSession {
        let name: RecentSessionName
        if titlesEnabled, let title = session.title, !title.isEmpty {
            name = .title(title)
        } else if let project = session.projectLabel, !project.isEmpty {
            name = .project(project)
        } else if !session.sessionId.isEmpty {
            name = .sessionID(String(decoding: session.sessionId.utf16.prefix(12), as: UTF16.self))
        } else {
            name = .none
        }
        var cacheSession = session
        cacheSession.client = ModelAliasResolver.jsLowercased(ModelAliasResolver.jsTrimmed(session.client))
        return RecentSession(
            id: session.id,
            session: session,
            client: cacheSession.client,
            name: name,
            modelLabel: modelLabel(session),
            modelShares: modelShares(session),
            activityTime: session.activityTime,
            state: state,
            context: state == .idle ? nil : SessionLive.contextReading(session),
            promptCache: SessionLive.promptCache(cacheSession, now: now)
        )
    }

    /// Sessions running at `now`.
    public static func runningCount(sessions: [HubSession], now: Date = Date()) -> Int {
        sessions.reduce(0) { $0 + (SessionLive.isRunning($1, now: now) ? 1 : 0) }
    }

    /// `homeSessionAgo`: rounded minutes, then rounded hours, then rounded
    /// days; nil without a time.
    public static func age(of time: Date?, now: Date = Date()) -> SessionAge? {
        let last = SessionLive.milliseconds(time)
        guard last > 0 else { return nil }
        let minutes = JSCompat.round(Double(max(0, SessionLive.milliseconds(now) - last)) / 60_000)
        if minutes < 1 { return .justNow }
        if minutes < 60 { return .minutes(Int(minutes)) }
        let hours = JSCompat.round(minutes / 60)
        if hours < 24 { return .hours(Int(hours)) }
        // Bounded well inside a 32-bit `Int` (Apple Watch): ±8.64e15 ms.
        return .days(Int(min(JSCompat.round(hours / 24), 1e8)))
    }

    // MARK: Hints

    /// `sessionBreakdownIncomplete`: some session details were left out of
    /// the upload (`sessions.incomplete`); only today and month have them.
    public static func isIncomplete(stats: HubStats, period: UsagePeriodKind) -> Bool {
        isIncomplete(omitted: stats.sessionDetailsOmitted, period: period)
    }

    /// `isIncomplete(stats:period:)` for a period selection; fixed ranges
    /// have no session list, so never.
    public static func isIncomplete(stats: HubStats, selection: PeriodSelection) -> Bool {
        guard let kind = selection.nativeKind else { return false }
        return isIncomplete(stats: stats, period: kind)
    }

    /// The same hint for one device's own lists.
    public static func isIncomplete(device: DeviceSummary, period: UsagePeriodKind) -> Bool {
        isIncomplete(omitted: device.sessionDetailsOmitted, period: period)
    }

    static func isIncomplete(omitted: [UsagePeriodKind: Int], period: UsagePeriodKind) -> Bool {
        switch period {
        case .today, .month: return (omitted[period] ?? 0) > 0
        case .allTime: return false
        }
    }

    /// `archivedSessionCount`: distinct archived sessions across the periods.
    public static func archivedCount(stats: HubStats) -> Int {
        var keys = Set<String>()
        for period in [stats.today, stats.month, stats.allTime] {
            for session in period.sessions where !isReasonixSynthetic(session) && session.isArchived {
                keys.insert("\(session.client):\(session.sessionId)")
            }
        }
        return keys.count
    }

    // MARK: Per-session values

    /// `sessionModelLabel`: the models with tokens, sorted.
    public static func modelLabel(_ session: HubSession) -> SessionModelLabel {
        let models = session.models.filter { $0.value > 0 }.map(\.key)
        switch models.count {
        case 0: return .none
        case 1: return .single(models[0])
        default: return .count(models.count)
        }
    }

    /// `sessionModelTooltipEntries`: with two or more models, each model's
    /// tokens and share (heaviest first), plus the unclaimed remainder.
    public static func modelShares(_ session: HubSession) -> [SessionModelShare] {
        let entries = session.models
            .filter { $0.value > 0 }
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                let order = UsageRowCollation.compare(left.key, right.key)
                return order != 0 ? order < 0 : left.key.utf16.lexicographicallyPrecedes(right.key.utf16)
            }
        guard entries.count >= 2 else { return [] }
        let total = session.totalTokens
        let attributed = entries.reduce(0) { $0 + $1.value }
        let denominator = Double(max(total, attributed))
        let named = entries.filter { !$0.key.isEmpty }
        var rows = named.map { entry in
            SessionModelShare(model: entry.key, tokens: entry.value, percent: denominator > 0 ? Double(entry.value) / denominator * 100 : 0)
        }
        let unlabeled = attributed - named.reduce(0) { $0 + $1.value }
        let unattributed = unlabeled + max(0, total - attributed)
        if unattributed > 0 {
            rows.append(SessionModelShare(model: nil, tokens: unattributed, percent: Double(unattributed) / denominator * 100))
        }
        return rows
    }

    /// `sessionIdLabel`: the UUID(s) in a session id, a rollout file's UUID
    /// or suffix, nothing for timestamp-only and Reasonix stats ids, else the
    /// raw id. Nil when there is nothing to show.
    public static func sessionIDLabel(_ id: String) -> String? {
        let ids = sessionIDs(id)
        return ids.isEmpty ? nil : ids.joined(separator: " · ")
    }

    /// The pieces `sessionIDLabel` joins.
    public static func sessionIDs(_ id: String) -> [String] {
        let raw = ModelAliasResolver.jsTrimmed(id)
        guard !raw.isEmpty else { return [] }
        let lower = raw.lowercased()
        let hasReasonixPrefix = lower.hasPrefix("reasonix:")
        let reasonixLabel = hasReasonixPrefix ? String(raw.dropFirst("reasonix:".count)) : raw
        if reasonixLabel.lowercased().hasPrefix("reasonix-stats:") { return [] }
        if hasReasonixPrefix { return [reasonixLabel] }
        let uuids = IDPatterns.uuid.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap { match in
            Range(match.range, in: raw).map { String(raw[$0]) }
        }
        if uuids.count > 1 { return uuids }
        if let match = IDPatterns.rollout.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let rest = Range(match.range(at: 1), in: raw) {
            return [uuids.first ?? String(raw[rest])]
        }
        if IDPatterns.timestamp.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil { return [] }
        return [raw]
    }

    /// `compactSessionTime`: `HH:mm` when `date` falls on the same local day
    /// as `now`, else `MM/DD HH:mm` (Gregorian, 24-hour, zero-padded, in
    /// `calendar`'s time zone). Nil without a date.
    public static func compactTime(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        compactTime(date, now: now, clock: clock(calendar))
    }

    static func compactTime(_ date: Date?, now: Date, clock: Calendar) -> String? {
        guard let date, SessionLive.milliseconds(date) != 0 else { return nil }
        let parts = clock.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let today = clock.dateComponents([.year, .month, .day], from: now)
        let time = "\(pad2(parts.hour ?? 0)):\(pad2(parts.minute ?? 0))"
        if parts.year == today.year, parts.month == today.month, parts.day == today.day { return time }
        return "\(pad2(parts.month ?? 0))/\(pad2(parts.day ?? 0)) \(time)"
    }

    /// `sessionTokenRate`: output tok/s over the timed entries, 0 without
    /// timing.
    public static func tokenRate(_ session: HubSession) -> Double {
        let duration = session.timedDurationMs
        let output = min(max(0, session.outputTokens), max(0, session.timedOutputTokens))
        guard duration > 0, output > 0 else { return 0 }
        return Double(output) * 1000 / duration
    }

    /// `tokenRateLabel`'s number: the rounded rate, nil when it rounds to 0.
    public static func roundedTokenRate(_ session: HubSession) -> Int? {
        let rate = JSCompat.round(tokenRate(session))
        guard rate > 0 else { return nil }
        return rate < Double(Int.max) ? Int(rate) : Int.max
    }

    /// `sessionCacheHitPercent`: cache reads over all input; nil when the
    /// session reports no cache traffic either way.
    public static func cacheHitPercent(_ session: HubSession) -> Double? {
        let read = max(0, session.cacheReadTokens)
        let write = max(0, session.cacheWriteTokens)
        guard read > 0 || write > 0 else { return nil }
        let input = max(0, session.inputTokens) + read + write
        return Double(read) / Double(input) * 100
    }

    /// `cacheHitLabel`: `"<1%"` for a sliver, else the rounded percent.
    public static func cacheHitLabel(_ session: HubSession) -> String? {
        cacheHitPercent(session).map(AttributionRows.detailPercentLabel)
    }

    /// `isBackgroundReviewSession`.
    public static func isBackgroundReview(_ session: HubSession) -> Bool {
        ModelAliasResolver.jsTrimmed(session.sessionKind ?? "") == HubSession.backgroundReviewKind
    }

    /// `isReasonixSyntheticSession`: Reasonix entries in an ordinary session
    /// map are untrusted stand-ins and never listed.
    public static func isReasonixSynthetic(_ session: HubSession) -> Bool {
        let client = normalizedID(session.client)
        let sessionID = normalizedID(session.sessionId)
        let key = normalizedID(session.id)
        return client == "reasonix"
            || client == "reasonix-stats"
            || sessionID.hasPrefix("reasonix-stats:")
            || sessionID.hasPrefix("reasonix:")
            || key.hasPrefix("reasonix:")
            || key.contains("reasonix-stats:")
    }

    // MARK: Helpers

    /// The desktop's `CLIENT_LABELS[client] || client`; nil without a client.
    static func clientLabel(_ client: String) -> String? {
        let id = ModelAliasResolver.jsTrimmed(client)
        guard !id.isEmpty else { return nil }
        return VendorCatalog.generatedClientLabels[id] ?? id
    }

    static func displayTitle(_ session: HubSession) -> String? {
        let title = ModelAliasResolver.jsTrimmed(session.title ?? "")
        return title.isEmpty ? nil : title
    }

    /// The desktop row `name` string, used only to break exact ties the way
    /// `localeCompare` does.
    static func nameSortKey(_ session: HubSession, titlesEnabled: Bool) -> String {
        if titlesEnabled, let title = displayTitle(session) { return title }
        let model: String
        switch modelLabel(session) {
        case .none: model = ""
        case let .single(id): model = id
        case let .count(count): model = "\(count) models"
        }
        return [clientLabel(session.client) ?? "Session", model].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func normalizedID(_ value: String) -> String {
        ModelAliasResolver.jsTrimmed(value).lowercased()
    }

    /// The desktop reads local time with Gregorian getters whatever the
    /// user's calendar; keep the caller's time zone only.
    static func clock(_ calendar: Calendar) -> Calendar {
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = calendar.timeZone
        return clock
    }

    static func pad2(_ value: Int) -> String {
        value < 10 && value >= 0 ? "0\(value)" : String(value)
    }

    enum IDPatterns {
        // `\d` is spelled [0-9]: JavaScript's matches ASCII digits only.
        static let uuid = regex("[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", options: [.caseInsensitive])
        static let rollout = regex("^rollout-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}[:-][0-9]{2}[:-][0-9]{2}-(.+)$")
        static let timestamp = regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}[:-][0-9]{2}")

        static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            // The patterns are literals; a failure is a programming error.
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern, options: options)
        }
    }
}

/// `String.prototype.localeCompare` without a locale, which V8 answers with
/// the ICU root collation: punctuation and symbols before digits before
/// letters, case-insensitive first (accents, then lower before upper break
/// the tie). Only used to break exact ties in row sorts, so it models the
/// characters ids and labels actually contain — ASCII exactly, other
/// scripts by code point.
enum UsageRowCollation {
    /// -1, 0 or 1, like `localeCompare`.
    static func compare(_ left: String, _ right: String) -> Int {
        if left == right { return 0 }
        let a = elements(left)
        let b = elements(right)
        for level in 0..<3 {
            let order = compareLevel(a.map { $0[level] }, b.map { $0[level] })
            if order != 0 { return order }
        }
        return 0
    }

    private static func compareLevel(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let a = a.filter { $0 != 0 }
        let b = b.filter { $0 != 0 }
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    /// Variable characters in root order (the ASCII ones).
    private static let variableOrder: [Character: UInt32] = {
        let order = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$"
        var map: [Character: UInt32] = ["\t": 1, "\n": 2, "\u{0B}": 3, "\u{0C}": 4, "\r": 5]
        for (index, character) in order.enumerated() { map[character] = UInt32(10 + index) }
        return map
    }()

    /// [primary, secondary, tertiary] per collation element; 0 = ignorable.
    private static func elements(_ value: String) -> [[UInt32]] {
        var result: [[UInt32]] = []
        for scalar in value.decomposedStringWithCanonicalMapping.unicodeScalars {
            let properties = scalar.properties
            if properties.generalCategory == .nonspacingMark || properties.generalCategory == .enclosingMark {
                result.append([0, 0x100 + scalar.value, 0])
                continue
            }
            if let weight = variableOrder[Character(scalar)] {
                result.append([weight, 1, 1])
            } else if scalar.isASCII, let digit = Int(String(scalar)) {
                result.append([1000 + UInt32(digit), 1, 1])
            } else if scalar.isASCII, properties.isAlphabetic {
                let lower = scalar.value | 0x20
                result.append([2000 + lower, 1, properties.isUppercase ? 2 : 1])
            } else if properties.isAlphabetic {
                let lower = properties.lowercaseMapping.unicodeScalars.first?.value ?? scalar.value
                result.append([0x10_0000 + lower, 1, properties.isUppercase ? 2 : 1])
            } else {
                result.append([500 + min(scalar.value, 400), 1, 1])
            }
        }
        return result
    }
}
