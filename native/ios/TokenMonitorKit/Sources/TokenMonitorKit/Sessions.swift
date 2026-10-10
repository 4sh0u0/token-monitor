import Foundation

/// A prompt-cache reading (`session.promptCache`): when the transcript showed
/// a cache write and the TTL tier it implies. An estimate, not server state;
/// `SessionLive` decides whether it is still worth showing.
public struct PromptCacheObservation: Sendable, Hashable {
    public var observedAt: Date
    /// 300, 1800 or 3600 on a current Hub; other values are kept as sent.
    public var ttlSeconds: Int

    public init(observedAt: Date, ttlSeconds: Int) {
        self.observedAt = observedAt
        self.ttlSeconds = ttlSeconds
    }

    /// `observedAt + ttlSeconds`.
    public var expiresAt: Date { observedAt.addingTimeInterval(TimeInterval(ttlSeconds)) }
}

/// One entry of `periods.today|month.sessions` (docs/API.md "Sessions"):
/// the Hub merges the same `client:sessionId` from every device and period
/// into one row.
public struct HubSession: Sendable, Hashable, Identifiable {
    /// The map key (`client:sessionId`), unique within a period.
    public var id: String
    /// The wire `client`, trimmed; empty when missing.
    public var client: String
    /// The wire `sessionId`, or the map key when it is missing (the
    /// desktop's `session.sessionId || key`).
    public var sessionId: String
    public var totalTokens: Int
    /// The known (priced) subtotal in USD.
    public var costUsd: Double
    /// Tokens the cost excludes because no price was known; nil when absent.
    public var unpricedTokens: Int?
    /// Usage-bearing replies (the desktop's "calls").
    public var messageCount: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    /// A subset of `outputTokens`; informational.
    public var reasoningTokens: Int
    /// 0 / 0 means no timing was reported, not zero speed.
    public var timedOutputTokens: Int
    public var timedDurationMs: Double
    public var startedAt: Date?
    public var lastUsedAt: Date?
    /// What the live context window holds and its size; 0 / 0 unless the
    /// collecting device read a recent transcript.
    public var contextTokens: Int
    public var contextWindow: Int
    /// Three states: `true` the turn finished, `false` a turn is in
    /// progress, nil the producer reports no turn boundary. Keep them apart.
    public var turnEnded: Bool?
    public var projectId: String?
    public var projectLabel: String?
    /// The synced title; nil when the wire sends `""` (titles not allowed).
    public var title: String?
    /// `background-review` (Codex auto review); nil for ordinary sessions.
    public var sessionKind: String?
    /// `codex-dots-local` for supplementary observations with incomplete
    /// coverage.
    public var usageSource: String?
    /// `observed-only` alongside `usageSource`.
    public var usageCoverage: String?
    public var promptCache: PromptCacheObservation?
    public var models: [String: Int]
    public var modelCosts: [String: Double]
    public var providers: [String: Int]
    /// `archived`, `deleted` or `sourceDeleted` is `true`: the source is gone.
    public var isArchived: Bool

    public init(
        id: String,
        client: String,
        sessionId: String? = nil,
        totalTokens: Int = 0,
        costUsd: Double = 0,
        unpricedTokens: Int? = nil,
        messageCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        reasoningTokens: Int = 0,
        timedOutputTokens: Int = 0,
        timedDurationMs: Double = 0,
        startedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        contextTokens: Int = 0,
        contextWindow: Int = 0,
        turnEnded: Bool? = nil,
        projectId: String? = nil,
        projectLabel: String? = nil,
        title: String? = nil,
        sessionKind: String? = nil,
        usageSource: String? = nil,
        usageCoverage: String? = nil,
        promptCache: PromptCacheObservation? = nil,
        models: [String: Int] = [:],
        modelCosts: [String: Double] = [:],
        providers: [String: Int] = [:],
        isArchived: Bool = false
    ) {
        self.id = id
        self.client = client
        self.sessionId = sessionId ?? id
        self.totalTokens = totalTokens
        self.costUsd = costUsd
        self.unpricedTokens = unpricedTokens
        self.messageCount = messageCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens
        self.timedOutputTokens = timedOutputTokens
        self.timedDurationMs = timedDurationMs
        self.startedAt = startedAt
        self.lastUsedAt = lastUsedAt
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.turnEnded = turnEnded
        self.projectId = projectId
        self.projectLabel = projectLabel
        self.title = title
        self.sessionKind = sessionKind
        self.usageSource = usageSource
        self.usageCoverage = usageCoverage
        self.promptCache = promptCache
        self.models = models
        self.modelCosts = modelCosts
        self.providers = providers
        self.isArchived = isArchived
    }

    /// The desktop's sort/activity time: `lastUsedAt || startedAt`.
    public var activityTime: Date? { lastUsedAt ?? startedAt }

    /// `sessionKind == "background-review"`.
    public var isBackgroundReview: Bool { sessionKind == Self.backgroundReviewKind }

    public static let backgroundReviewKind = "background-review"
}

extension HubSession {
    enum WireKeys: String, CodingKey {
        case client, sessionId, totalTokens, costUsd, unpricedTokens, messageCount
        case inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, reasoningTokens
        case timedOutputTokens, timedDurationMs, startedAt, lastUsedAt, contextTokens, contextWindow
        case turnEnded, projectId, projectLabel, title, sessionKind, usageSource, usageCoverage
        case promptCache, models, modelCosts, providers, archived, deleted, sourceDeleted
    }

    private enum PromptCacheKeys: String, CodingKey {
        case observedAt, ttlSeconds
    }

    init(key: String, wire container: KeyedDecodingContainer<WireKeys>) {
        func count(_ field: WireKeys) -> Int { nonNegative(container.lenientInt(field) ?? 0) }
        let promptCache: PromptCacheObservation?
        if let cache = try? container.nestedContainer(keyedBy: PromptCacheKeys.self, forKey: .promptCache),
           let observedAt = cache.lenientDate(.observedAt),
           let ttl = cache.lenientInt(.ttlSeconds) {
            promptCache = PromptCacheObservation(observedAt: observedAt, ttlSeconds: ttl)
        } else {
            promptCache = nil
        }
        self.init(
            id: key,
            client: container.lenientString(.client) ?? "",
            sessionId: container.lenientString(.sessionId),
            totalTokens: count(.totalTokens),
            costUsd: nonNegative(container.lenientDouble(.costUsd) ?? 0),
            unpricedTokens: container.lenientInt(.unpricedTokens).map(nonNegative),
            messageCount: count(.messageCount),
            inputTokens: count(.inputTokens),
            outputTokens: count(.outputTokens),
            cacheReadTokens: count(.cacheReadTokens),
            cacheWriteTokens: count(.cacheWriteTokens),
            reasoningTokens: count(.reasoningTokens),
            timedOutputTokens: count(.timedOutputTokens),
            timedDurationMs: nonNegative(container.lenientDouble(.timedDurationMs) ?? 0),
            startedAt: container.lenientDate(.startedAt),
            lastUsedAt: container.lenientDate(.lastUsedAt),
            contextTokens: count(.contextTokens),
            contextWindow: count(.contextWindow),
            turnEnded: container.strictBool(.turnEnded),
            projectId: container.lenientString(.projectId),
            projectLabel: container.lenientString(.projectLabel),
            title: container.lenientString(.title),
            sessionKind: container.lenientString(.sessionKind),
            usageSource: container.lenientString(.usageSource),
            usageCoverage: container.lenientString(.usageCoverage),
            promptCache: promptCache,
            models: container.lenientCountMap(.models),
            modelCosts: container.lenientNumberMap(.modelCosts).mapValues(nonNegative),
            providers: container.lenientCountMap(.providers),
            isArchived: container.strictBool(.archived) == true
                || container.strictBool(.deleted) == true
                || container.strictBool(.sourceDeleted) == true
        )
    }

    /// A `sessions` object. Entries that are not objects are dropped; the
    /// rest come back newest first (`lastUsedAt || startedAt`), then by id.
    static func sessions<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> [HubSession] {
        guard !container.isNullOrMissing(key),
              let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return [] }
        var rows: [HubSession] = []
        rows.reserveCapacity(nested.allKeys.count)
        for entry in nested.allKeys {
            guard let fields = try? nested.nestedContainer(keyedBy: WireKeys.self, forKey: entry) else { continue }
            rows.append(HubSession(key: entry.stringValue, wire: fields))
        }
        return rows.sorted(by: newestFirst)
    }

    static func newestFirst(_ left: HubSession, _ right: HubSession) -> Bool {
        let leftTime = left.activityTime?.timeIntervalSince1970 ?? 0
        let rightTime = right.activityTime?.timeIntervalSince1970 ?? 0
        if leftTime != rightTime { return leftTime > rightTime }
        return left.id < right.id
    }
}
